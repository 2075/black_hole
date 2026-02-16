#include <metal_stdlib>
using namespace metal;

// MARK: - Uniform Structs (must match Swift CameraUniforms / DiskUniforms / ObjectsUniforms)

struct CameraUniforms {
    float3 camPos;      float _pad0;
    float3 camRight;    float _pad1;
    float3 camUp;       float _pad2;
    float3 camForward;  float _pad3;
    float tanHalfFov;
    float aspect;
    int   moving;
    int   _pad4;
};

struct DiskUniforms {
    float disk_r1;
    float disk_r2;
    float disk_num;
    float thickness;
    float4 diskColor;
};

struct ObjectsUniforms {
    int   numObjects;
    float _pad0, _pad1, _pad2;
    float4 objPosRadius[16];
    float4 objColor[16];
    float  mass[16];
};

// MARK: - Constants

constant float SagA_rs  = 1.269e10;
constant float D_LAMBDA = 1e7;
constant float ESCAPE_R = 1e30;

// MARK: - Ray

struct Ray {
    float x, y, z, r, theta, phi;
    float dr, dtheta, dphi;
    float E, L;
};

Ray initRay(float3 pos, float3 dir) {
    Ray ray;
    ray.x = pos.x; ray.y = pos.y; ray.z = pos.z;
    ray.r = length(pos);
    ray.theta = acos(pos.z / ray.r);
    ray.phi = atan2(pos.y, pos.x);

    float dx = dir.x, dy = dir.y, dz = dir.z;
    ray.dr     = sin(ray.theta)*cos(ray.phi)*dx + sin(ray.theta)*sin(ray.phi)*dy + cos(ray.theta)*dz;
    ray.dtheta = (cos(ray.theta)*cos(ray.phi)*dx + cos(ray.theta)*sin(ray.phi)*dy - sin(ray.theta)*dz) / ray.r;
    ray.dphi   = (-sin(ray.phi)*dx + cos(ray.phi)*dy) / (ray.r * sin(ray.theta));

    ray.L = ray.r * ray.r * sin(ray.theta) * ray.dphi;
    float f = 1.0 - SagA_rs / ray.r;
    float dt_dL = sqrt((ray.dr*ray.dr)/f + ray.r*ray.r*(ray.dtheta*ray.dtheta + sin(ray.theta)*sin(ray.theta)*ray.dphi*ray.dphi));
    ray.E = f * dt_dL;

    return ray;
}

// MARK: - Intersection Tests

bool interceptBlackHole(Ray ray, float rs) {
    return ray.r <= rs;
}

struct HitInfo {
    float4 color;
    float3 center;
    float  radius;
    bool   hit;
};

HitInfo interceptObject(Ray ray, constant ObjectsUniforms &objs) {
    HitInfo info;
    info.hit = false;
    float3 P = float3(ray.x, ray.y, ray.z);
    for (int i = 0; i < objs.numObjects; ++i) {
        float3 center = objs.objPosRadius[i].xyz;
        float radius = objs.objPosRadius[i].w;
        if (distance(P, center) <= radius) {
            info.color = objs.objColor[i];
            info.center = center;
            info.radius = radius;
            info.hit = true;
            return info;
        }
    }
    return info;
}

// MARK: - Geodesic RHS & RK4

void geodesicRHS(Ray ray, thread float3 &d1, thread float3 &d2) {
    float r = ray.r, theta = ray.theta;
    float dr = ray.dr, dtheta = ray.dtheta, dphi = ray.dphi;
    float f = 1.0 - SagA_rs / r;
    float dt_dL = ray.E / f;

    d1 = float3(dr, dtheta, dphi);
    d2.x = -(SagA_rs / (2.0 * r*r)) * f * dt_dL * dt_dL
          + (SagA_rs / (2.0 * r*r * f)) * dr * dr
          + r * (dtheta*dtheta + sin(theta)*sin(theta)*dphi*dphi);
    d2.y = -2.0*dr*dtheta/r + sin(theta)*cos(theta)*dphi*dphi;
    d2.z = -2.0*dr*dphi/r - 2.0*cos(theta)/(sin(theta)) * dtheta * dphi;
}

void rk4Step(thread Ray &ray, float dL) {
    float3 k1a, k1b;
    geodesicRHS(ray, k1a, k1b);

    ray.r      += dL * k1a.x;
    ray.theta  += dL * k1a.y;
    ray.phi    += dL * k1a.z;
    ray.dr     += dL * k1b.x;
    ray.dtheta += dL * k1b.y;
    ray.dphi   += dL * k1b.z;

    ray.x = ray.r * sin(ray.theta) * cos(ray.phi);
    ray.y = ray.r * sin(ray.theta) * sin(ray.phi);
    ray.z = ray.r * cos(ray.theta);
}

bool crossesEquatorialPlane(float3 oldPos, float3 newPos, float r1, float r2) {
    bool crossed = (oldPos.y * newPos.y < 0.0);
    float r = length(float2(newPos.x, newPos.z));
    return crossed && (r >= r1 && r <= r2);
}

// MARK: - Compute Kernel

kernel void geodesicKernel(
    texture2d<float, access::write> outImage [[texture(0)]],
    constant CameraUniforms &cam             [[buffer(0)]],
    constant DiskUniforms   &disk            [[buffer(1)]],
    constant ObjectsUniforms &objs           [[buffer(2)]],
    uint2 gid                                [[thread_position_in_grid]]
) {
    int WIDTH  = outImage.get_width();
    int HEIGHT = outImage.get_height();

    if (int(gid.x) >= WIDTH || int(gid.y) >= HEIGHT) return;

    // Initialize ray direction from pixel coordinates
    float u = (2.0 * (float(gid.x) + 0.5) / float(WIDTH) - 1.0) * cam.aspect * cam.tanHalfFov;
    float v = (1.0 - 2.0 * (float(gid.y) + 0.5) / float(HEIGHT)) * cam.tanHalfFov;
    float3 dir = normalize(u * cam.camRight - v * cam.camUp + cam.camForward);
    Ray ray = initRay(cam.camPos, dir);

    float4 color = float4(0.0);
    float3 prevPos = float3(ray.x, ray.y, ray.z);

    bool hitBlackHole = false;
    bool hitDisk      = false;
    HitInfo hitInfo;
    hitInfo.hit = false;

    int steps = 60000;

    for (int i = 0; i < steps; ++i) {
        if (interceptBlackHole(ray, SagA_rs)) { hitBlackHole = true; break; }
        rk4Step(ray, D_LAMBDA);

        float3 newPos = float3(ray.x, ray.y, ray.z);
        if (crossesEquatorialPlane(prevPos, newPos, disk.disk_r1, disk.disk_r2)) {
            hitDisk = true;
            break;
        }
        hitInfo = interceptObject(ray, objs);
        if (hitInfo.hit) break;
        prevPos = newPos;
        if (ray.r > ESCAPE_R) break;
    }

    if (hitDisk) {
        float r_frac = clamp(length(float3(ray.x, ray.y, ray.z)) / disk.disk_r2, 0.0, 1.0);
        float3 innerCol = disk.diskColor.rgb * 0.3;
        float3 outerCol = disk.diskColor.rgb;
        float3 diskCol = mix(innerCol, outerCol, r_frac);
        color = float4(diskCol, clamp(r_frac, 0.1, 1.0));

    } else if (hitBlackHole) {
        color = float4(0.0, 0.0, 0.0, 1.0);

    } else if (hitInfo.hit) {
        float3 P = float3(ray.x, ray.y, ray.z);
        float3 N = normalize(P - hitInfo.center);
        float3 V = normalize(cam.camPos - P);
        float ambient = 0.1;
        float diff = max(dot(N, V), 0.0);
        float intensity = ambient + (1.0 - ambient) * diff;
        float3 shaded = hitInfo.color.rgb * intensity;
        color = float4(shaded, hitInfo.color.a);

    } else {
        color = float4(0.0);
    }

    outImage.write(color, gid);
}
