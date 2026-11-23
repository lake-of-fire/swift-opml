//
//  OPMLParser.swift
//  OPML
//
//  Created by wong on 12/16/25.
//

import Foundation


public class OPMLParser: NSObject, XMLParserDelegate {
    private struct Element {
        let name: String
        let defaultNamespace: String
    }

    private let xmlParser: XMLParser
    private var parsedOPML: OPML?
    private var elements: [Element] = []
    private var hasBody = false
    private var hasInvalidStructure = false
    
    // Parsing state
    private var currentCharacters: String = ""
    private var outlineStack: [OPML.Outline] = []
    
    // Header information
    private var version: String = "2.0"
    private var title: String?
    private var dateCreated: Date?
    private var dateModified: Date?
    private var ownerName: String?
    private var ownerEmail: String?
    private var ownerID: URL?
    private var docs: URL?
    private var outlines: [OPML.Outline] = []
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
    
    public init(contentsOf url: URL) throws {
        guard let xmlParser = XMLParser(contentsOf: url) else { 
            throw Error.unableToOpenURL(url) 
        }
        self.xmlParser = xmlParser
        super.init()
        xmlParser.delegate = self
    }
    
    public init(data: Data) throws {
        self.xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }
    
    public func parse() throws -> OPML {
        let didParse = xmlParser.parse()
        guard !hasInvalidStructure else {
            throw Error.invalidDocument
        }
        guard didParse else {
            if let error = xmlParser.parserError {
                throw Error.parseError(error)
            } else {
                throw Error.invalidDocument
            }
        }
        
        guard hasBody, let parsedOPML = parsedOPML else {
            throw Error.invalidDocument
        }
        return parsedOPML
    }
    
    // MARK: - Convenience Methods
    
    public static func parse(contentsOf url: URL) throws -> OPML {
        let parser = try OPMLParser(contentsOf: url)
        return try parser.parse()
    }
    
    public static func parse(data: Data) throws -> OPML {
        let parser = try OPMLParser(data: data)
        return try parser.parse()
    }
    
    // MARK: - XMLParserDelegate
    
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        // Keep XMLParser's qualified attribute names for OPML extensions.
        // In this mode it also supplies the default namespace declaration as an attribute.
        let defaultNamespace = attributeDict["xmlns"] ?? elements.last?.defaultNamespace ?? ""
        let name = defaultNamespace.isEmpty ? elementName : ""
        guard !hasInvalidStructure, canOpenElement(named: name) else {
            hasInvalidStructure = true
            parser.abortParsing()
            return
        }
        elements.append(Element(name: name, defaultNamespace: defaultNamespace))
        currentCharacters = ""
        
        switch name {
        case "opml":
            // Extract version from opml element
            version = attributeDict["version"] ?? "2.0"
        case "body":
            hasBody = true
        case "outline":
            let text = attributeDict["text"] ?? ""
            let title = attributeDict["title"] ?? attributeDict["text"] ?? ""
            
            let attributes = attributeDict.map { OPML.Attribute(name: $0.key, value: $0.value) }
            
            let outline = OPML.Outline(
                text: text,
                title: title,
                attributes: attributes.isEmpty ? nil : attributes,
                children: nil
            )
            
            if outlineStack.isEmpty {
                // Top-level outline
                outlines.append(outline)
            }
            
            outlineStack.append(outline)
        default:
            break
        }
    }

    private func canOpenElement(named name: String) -> Bool {
        guard let parent = elements.last else { return name == "opml" }
        switch name {
        case "opml":
            return false
        case "body":
            return parent.name == "opml" && !hasBody
        case "outline":
            return parent.name == "body" || parent.name == "outline"
        default:
            return true
        }
    }
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentCharacters += string
    }
    
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard !hasInvalidStructure, let element = elements.popLast() else { return }
        defer { currentCharacters = "" }
        
        switch element.name {
        case "opml":
            // Create the final OPML object
            parsedOPML = OPML(
                version: version,
                title: title,
                dateCreated: dateCreated,
                dateModified: dateModified,
                ownerName: ownerName,
                ownerEmail: ownerEmail,
                ownerID: ownerID,
                docs: docs,
                outlines: outlines
            )
        case "title":
            let value = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
            title = value.isEmpty ? nil : value
        case "dateCreated":
            dateCreated = Self.dateFormatter.date(from: currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines))
        case "dateModified":
            dateModified = Self.dateFormatter.date(from: currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines))
        case "ownerName":
            let value = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
            ownerName = value.isEmpty ? nil : value
        case "ownerEmail":
            let value = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
            ownerEmail = value.isEmpty ? nil : value
        case "ownerId":
            ownerID = URL(string: currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines))
        case "docs":
            docs = URL(string: currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines))
        case "outline":
            // Handle nested outlines
            if outlineStack.count > 1 {
                let childOutline = outlineStack.removeLast()
                let parentOutline = outlineStack[outlineStack.count - 1]
                
                // Create a new parent with updated children
                var children = parentOutline.children ?? []
                children.append(childOutline)
                
                let updatedParent = OPML.Outline(
                    text: parentOutline.text,
                    title: parentOutline.title,
                    attributes: parentOutline.attributes,
                    children: children
                )
                
                // Replace the parent in the stack
                outlineStack[outlineStack.count - 1] = updatedParent
                
                // The live top-level parent is the last root appended when it opened.
                // Display labels can be shared by different outlines.
                if outlineStack.count == 1 {
                    outlines[outlines.count - 1] = updatedParent
                }
            } else {
                // Top-level outline - just remove from stack
                outlineStack.removeLast()
            }
        default:
            break
        }
    }
    
    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Swift.Error) {
        // Error will be handled in parse() method
    }
    
    public enum Error: LocalizedError {
        case invalidDocument
        case parseError(Swift.Error)
        case unableToOpenURL(URL)
        
        public var errorDescription: String? {
            switch self {
            case .invalidDocument: 
                return "Invalid or missing XML document"
            case .parseError(let error): 
                return "XML parsing error: \(error.localizedDescription)"
            case .unableToOpenURL(let url): 
                return "Unable to open a file at the given URL \(url)"
            }
        }
    }
}
