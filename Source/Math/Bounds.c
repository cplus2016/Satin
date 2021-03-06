//
//  Bounds.c
//  Pods
//
//  Created by Reza Ali on 11/30/20.
//
#include <stdio.h>
#include <simd/simd.h>

#include "Bounds.h"

Bounds computeBoundsFromVertices(Vertex *vertices, int count)
{
    if(count > 0) {
        simd_float3 min = simd_make_float3(INFINITY, INFINITY, INFINITY);
        simd_float3 max = simd_make_float3(-INFINITY, -INFINITY, -INFINITY);
        for (int i = 0; i < count; i++) {
            Vertex *vertex = &vertices[i];
            simd_float4 pos = vertex->position;
            
            min.x = simd_min(pos.x, min.x);
            min.y = simd_min(pos.y, min.y);
            min.z = simd_min(pos.z, min.z);
            
            max.x = simd_max(pos.x, max.x);
            max.y = simd_max(pos.y, max.y);
            max.z = simd_max(pos.z, max.z);
        }        
        return (Bounds) { .min = min, .max = max };
    }
    return (Bounds) { .min = simd_make_float3(0.0, 0.0, 0.0), .max = simd_make_float3(0.0, 0.0, 0.0)};
}

Bounds computeBoundsFromVerticesAndTransform(Vertex *vertices, int count, simd_float4x4 transform)
{
    if(count > 0) {
        simd_float3 min = simd_make_float3(INFINITY, INFINITY, INFINITY);
        simd_float3 max = simd_make_float3(-INFINITY, -INFINITY, -INFINITY);
        for (int i = 0; i < count; i++) {
            Vertex *vertex = &vertices[i];
            simd_float4 pos = simd_mul(transform, vertex->position);
            
            min.x = simd_min(pos.x, min.x);
            min.y = simd_min(pos.y, min.y);
            min.z = simd_min(pos.z, min.z);
            
            max.x = simd_max(pos.x, max.x);
            max.y = simd_max(pos.y, max.y);
            max.z = simd_max(pos.z, max.z);
        }
        return (Bounds) { .min = min, .max = max };
    }
    return (Bounds) { .min = simd_make_float3(0.0, 0.0, 0.0), .max = simd_make_float3(0.0, 0.0, 0.0)};
}

Bounds mergeBounds(Bounds a, Bounds b)
{
    simd_float3 amin = simd_min(a.min, a.max);
    simd_float3 amax = simd_max(a.min, a.max);
    
    simd_float3 bmin = simd_min(b.min, b.max);
    simd_float3 bmax = simd_max(b.min, b.max);
    
    simd_float3 min = simd_min(amin, bmin);
    simd_float3 max = simd_max(amax, bmax);
    
    return (Bounds) { .min = min, .max = max };
}

Bounds transformBounds(Bounds a, simd_float4x4 transform) {
    simd_float3 v0 = simd_make_float3(simd_mul(transform, simd_make_float4(a.min.x, a.min.y, a.max.z, 1.0)));
    simd_float3 v1 = simd_make_float3(simd_mul(transform, simd_make_float4(a.max.x, a.min.y, a.max.z, 1.0)));
    simd_float3 v2 = simd_make_float3(simd_mul(transform, simd_make_float4(a.max, 1.0)));
    simd_float3 v3 = simd_make_float3(simd_mul(transform, simd_make_float4(a.min.x, a.max.y, a.max.z, 1.0)));
    simd_float3 v4 = simd_make_float3(simd_mul(transform, simd_make_float4(a.min, 1.0)));
    simd_float3 v5 = simd_make_float3(simd_mul(transform, simd_make_float4(a.max.x, a.min.y, a.min.z, 1.0)));
    simd_float3 v6 = simd_make_float3(simd_mul(transform, simd_make_float4(a.max.x, a.max.y, a.min.z,  1.0)));
    simd_float3 v7 = simd_make_float3(simd_mul(transform, simd_make_float4(a.min.x, a.max.y, a.min.z, 1.0)));
    
    simd_float3 min = simd_min(v0, v1);
    min = simd_min(min, v2);
    min = simd_min(min, v3);
    min = simd_min(min, v4);
    min = simd_min(min, v5);
    min = simd_min(min, v6);
    min = simd_min(min, v7);
    
    simd_float3 max = simd_max(v0, v1);
    max = simd_max(max, v2);
    max = simd_max(max, v3);
    max = simd_max(max, v4);
    max = simd_max(max, v5);
    max = simd_max(max, v6);
    max = simd_max(max, v7);
    
    return (Bounds) { .min = min, .max = max };
}


