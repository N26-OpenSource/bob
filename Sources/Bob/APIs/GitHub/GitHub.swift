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
import HTTP
import Vapor

enum GitHubError: LocalizedError {
    case invalidBranch(name: String)
    case invalidParam(String)
    case invalidStatus(httpStatus: UInt, body: String?)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .decoding(let message):
            return "Decoding error: \(message)"
        case .invalidBranch(let name):
            return "The branch '\(name)' does not exists"
        case .invalidParam(let param):
            return "Invalid parameter '\(param)'"
        case .invalidStatus(let httpStatus, let body):
            var message = "Invalid response status '\(httpStatus)')"
            body.flatMap { message += " body: \($0)" }
            return message
        }
    }
}

/// Used for communicating with the GitHub api
public class GitHub {
    /// Configuration needed for authentication with the api
    public struct Configuration {
        public let username: String
        public let personalAccessToken: String
        public let repoUrl: String
        /// Initializer for the configuration
        ///
        /// - Parameters:
        ///   - username: Username of a user
        ///   - personalAccessToken: Personal access token for that user. Make sure it has repo read/write for the repo you intend to use
        ///   - repoUrl: Url of the repo. Alogn the lines of https://api.github.com/repos/{owner}/{repo}
        public init(username: String, personalAccessToken: String, repoUrl: String) {
            self.username = username
            self.personalAccessToken = personalAccessToken
            self.repoUrl = repoUrl
        }
    }
    
    private let authorization: BasicAuthorization
    private let repoUrl: String
    private let container: Container

    public var worker: Worker {
        return container
    }

    public init(config: Configuration, container: Container) {
        self.authorization = BasicAuthorization(username: config.username, password: config.personalAccessToken)
        self.repoUrl = config.repoUrl
        self.container = container
    }
    
    private func uri(at path: String) -> String {
        return self.repoUrl + path
    }

    // MARK: Repository APIs

    public func branches() throws -> Future<[GitHub.Repos.Branch]> {
        return try get(uri(at: "/branches?per_page=100"))
    }
    
    public func branch(_ branch: GitHub.Repos.Branch.BranchName) throws -> Future<GitHub.Repos.BranchDetail> {
        return try get(uri(at: "/branches/" + branch))
    }

    /// Lists the content of a directory
    public func contents(at path: String, on branch: GitHub.Repos.Branch.BranchName) throws -> Future<[GitHub.Repos.GitContent]> {
        return try get(uri(at: "/contents/\(path)?ref=" + branch))
    }

    /// Content of a single file
    public func content(at path: String, on branch: GitHub.Repos.Branch.BranchName) throws -> Future<GitHub.Repos.GitContent> {
        return try get(uri(at: "/contents/\(path)?ref=" + branch))
    }

    public func tags() throws -> Future<[GitHub.Repos.Tag]> {
        return try get(uri(at: "/tags"))
    }

    /// Returns a list of commits in reverse chronological order
    ///
    /// - Parameters:
    ///   - sha: Starting commit
    ///   - page: Index of the requested page
    ///   - perPage: Number of commits per page
    ///   - path: Directory within repository (optional). Only commits with files touched within path will be returned
    public func commits(after sha: String? = nil, page: Int? = nil, perPage: Int? = nil, path: String? = nil) throws -> Future<[GitHub.Repos.Commit]> {
        var components = URLComponents(string: "")!
        var items = [URLQueryItem]()
        components.path = "/commits"

        if let sha = sha {
            items.append(URLQueryItem(name: "sha", value: sha))
        }
        if let page = page {
            items.append(URLQueryItem(name: "page", value: "\(page)"))
        }

        if let perPage = perPage {
            items.append(URLQueryItem(name: "per_page", value: "\(perPage)"))
        }

        if let path = path {
            items.append(URLQueryItem(name: "path", value: "\(path)"))
        }
        components.queryItems = items
        guard let url = components.url else { throw GitHubError.invalidParam("Could not create commit URL") }
        let uri = self.uri(at: url.absoluteString)

        return try get(uri)
    }

    // MARK: - Git APIs

    public func gitCommit(sha: GitHub.Git.Commit.SHA) throws -> Future<GitHub.Git.Commit> {
        return try get(uri(at: "/git/commits/" + sha))
    }

    public func gitBlob(sha: Git.TreeItem.SHA) throws -> Future<GitHub.Git.Blob> {
        return try get(uri(at: "/git/blobs/" + sha))
    }

    public func newBlob(data: String) throws -> Future<GitHub.Git.Blob.New.Response> {
        let blob = GitHub.Git.Blob.New(content: data)
        return try post(body: blob, to: uri(at: "/git/blobs"))
    }

    public func trees(for treeSHA: GitHub.Git.Tree.SHA) throws -> Future<GitHub.Git.Tree> {
        return try self.get(uri(at: "/git/trees/" + treeSHA + "?recursive=1"))
    }

    public func newTree(tree: Tree.New) throws -> Future<Tree> {
        return try post(body: tree, to: uri(at: "/git/trees"))
    }

    /// https://developer.github.com/v3/git/commits/#create-a-commit
    public func newCommit(by author: Author, message: String, parentSHA: String, treeSHA: String) throws -> Future<GitHub.Git.Commit> {
        let body = GitCommit.New(message: message, tree: treeSHA, parents: [parentSHA], author: author)
        return try post(body: body, to: uri(at: "/git/commits"))
    }

    public func updateRef(to sha: GitHub.Git.Commit.SHA, on branch: GitHub.Repos.Branch.BranchName) throws -> Future<GitHub.Git.Reference> {
        let body = GitHub.Git.Reference.Patch(sha: sha)
        return try post(body: body, to: uri(at: "/git/refs/heads/" + branch), patch: true)
    }

    // MARK: - Private

    private func get<T: Content>(_ uri: String) throws -> Future<T> {
        return try container.client().get(uri, using: GitHub.decoder, authorization: authorization)
    }

    private func post<Body: Content, T: Content>(body: Body, to uri: String, patch: Bool = false ) throws -> Future<T> {
        return try container.client().post(body: body, to: uri, encoder: GitHub.encoder, using: GitHub.decoder, method: patch ? .PATCH : .POST, authorization: authorization)
    }
}
