//
//  SampleServers.swift
//  Django Files
//
//  Created by Michael on 2/15/25.
//

import Foundation
import SwiftData

extension DjangoFilesSession {
    static func insertSampleData(modelContext: ModelContext) {
        // Add the animal categories to the model context.
        modelContext.insert(DjangoFilesSession(url: "https://d.luac.es"))
    }
    
    static func reloadSampleData(modelContext: ModelContext) {
        do {
            try modelContext.delete(model: DjangoFilesSession.self)
            insertSampleData(modelContext: modelContext)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}
