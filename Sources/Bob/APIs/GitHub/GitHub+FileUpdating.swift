/*
 * Copyright (c) 2017 N26 GmbH.
 *
 * This file is part of Bob.
 *
 * Bob is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Bob is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Bob.  If not, see <http://www.gnu.org/licenses/>.
 */

import Foundation
import Dispatch

public protocol ItemUpdater {
    
    func itemsToUpdate(from items: [TreeItem]) -> [TreeItem]
    func update(_ item: TreeItem, content: String) throws -> String
    
}

fileprivate class BatchItemUpdater {
    
    private let items: [TreeItem]
    private let updater: ItemUpdater
    init(items: [TreeItem], updater: ItemUpdater) {
        self.items = items
        self.updater = updater
    }
    
    func update(using api: GitHub) throws -> [TreeItem] {
        let itemsToUpdate = self.updater.itemsToUpdate(from: self.items)
        let updater = self.updater
        return try itemsToUpdate.map {
            let content = try api.content(forBlobWith: $0.sha)
            
            let newContent = try updater.update($0, content: content)
            
            let newBlobSHA = try api.newBlob(with: newContent)
            
            return TreeItem(path: $0.path, mode: $0.mode, type: $0.type, sha: newBlobSHA)
        }
    }
    
}

public extension GitHub {
    
    public func newCommit(updatingItemsWith updater: ItemUpdater, on branch: BranchName, by author: Author, message: String) throws {
        
        try self.assertBranchExists(branch)
        let currentCommitSHA = try self.currentCommitSHA(on: branch)
        let treeSHA = try self.treeSHA(forCommitWith: currentCommitSHA)
        let items = try self.treeItems(forTreeWith: treeSHA)
        let updatedItems = try BatchItemUpdater(items: items, updater: updater).update(using: self)
        let newTreeSHA = try self.newTree(withBaseSHA: treeSHA, items: updatedItems)
        let newCommitSHA = try self.newCommit(by: author, message: message, parentSHA: currentCommitSHA, treeSHA: newTreeSHA)
        try self.updateRef(to: newCommitSHA, on: branch)
    }
    
}
