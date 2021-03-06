//
//  Helpers.swift
//  Pods
//
//  Created by Reza Ali on 11/24/20.
//

import Foundation

public func getMeshes(_ object: Object, _ recursive: Bool, _ invisible: Bool) -> [Mesh] {
    var results: [Mesh] = []
    if invisible || object.visible {
        if object is Mesh, let mesh = object as? Mesh, let material = mesh.material, let _ = material.pipeline {
            let geometry = mesh.geometry
            if !geometry.vertexData.isEmpty, mesh.instanceCount > 0 {
                results.append(object as! Mesh)
            }
        }
        
        if recursive {
            let children = object.children
            for child in children {
                results.append(contentsOf: getMeshes(child, recursive, invisible))
            }
        }
    }
    return results
}
