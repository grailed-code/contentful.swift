//
//  Decoding.swift
//  Contentful
//
//  Created by Boris Bügling on 29/09/15.
//  Copyright © 2015 Contentful GmbH. All rights reserved.
//

import Decodable
import Foundation

private let DEFAULT_LOCALE = "en-US"

extension UInt: Castable {}

extension Asset: Decodable {
    /// Decode JSON for an Asset
    public static func decode(json: AnyObject) throws -> Asset {
        let urlString: String = try json => "fields" => "file" => "url"
        // FIXME: Scheme should not be hardcoded
        guard let url = NSURL(string: "https:\(urlString)") else {
            throw ContentfulError.InvalidURL(string: urlString)
        }

        return try Asset(
            sys: (json => "sys") as! [String : AnyObject],
            fields: (json => "fields") as! [String : AnyObject],

            identifier: json => "sys" => "id",
            type: json => "sys" => "type",
            URL: url
        )
    }
}

extension ContentfulArray: Decodable {
    private static func resolveLink(value: Any, _ includes: [String:Resource]) -> Any? {
        if let link = value as? [String:AnyObject],
            sys = link["sys"] as? [String:AnyObject],
            identifier = sys["id"] as? String,
            type = sys["linkType"] as? String,
            include = includes["\(type)_\(identifier)"] {
                return include
        }

        return nil
    }

    private static func resolveLinks(entry: Entry, _ includes: [String:Resource]) -> Entry {
        var localizedFields = [String:[String:Any]]()

        entry.localizedFields.forEach { locale, entryFields in
            var fields = entryFields

            entryFields.forEach { field in
                if let include = resolveLink(field.1, includes) {
                    fields[field.0] = include
                }

                if let links = field.1 as? [[String:AnyObject]] {
                    // This drops any unresolvable links automatically
                    let includes = links.map { resolveLink($0, includes) }.flatMap { $0 }
                    if includes.count > 0 {
                        fields[field.0] = includes
                    }
                }
            }

            localizedFields[locale] = fields
        }

        return Entry(entry: entry, localizedFields: localizedFields)
    }

    /// Decode JSON for an Array
    public static func decode(json: AnyObject) throws -> ContentfulArray {
        var includes = [String:Resource]()
        let jsonIncludes = try? json => "includes" as! [String:AnyObject]

        if let jsonIncludes = jsonIncludes {
            try Asset.decode(jsonIncludes, &includes)
            try Entry.decode(jsonIncludes, &includes)
        }

        var items: [T] = try json => "items"

        for item in items {
            if let resource = item as? Resource {
                includes[resource.key] = resource
            }
        }

        for (key, resource) in includes {
            if let entry = resource as? Entry {
                includes[key] = resolveLinks(entry, includes)
            }
        }

        items = items.map { (item) in
            if let entry = item as? Entry {
                return resolveLinks(entry, includes) as! T
            }
            return item
        }

        return try ContentfulArray(
            items: items,

            limit: json => "limit",
            skip: json => "skip",
            total: json => "total"
        )
    }
}

extension ContentType: Decodable {
    /// Decode JSON for a Content Type
    public static func decode(json: AnyObject) throws -> ContentType {
        return try ContentType(
            sys: (json => "sys") as! [String : AnyObject],
            fields: json => "fields",

            identifier: json => "sys" => "id",
            name: json => "name",
            type: json => "sys" => "type"
        )
    }
}

extension Entry: Decodable {
    // Cannot cast directly from [String:AnyObject] => [String:Any]
    private static func convert(fields: [String:AnyObject]) -> [String:Any] {
        var result = [String:Any]()
        fields.forEach { result[$0.0] = $0.1 }
        return result
    }

    /// Decode JSON for an Entry
    public static func decode(json: AnyObject) throws -> Entry {
        let fields: [String:AnyObject] = try json => "fields"
        let locale: String? = try? json => "sys" => "locale"

        var localizedFields = [String:[String:Any]]()

        if let locale = locale {
            localizedFields[locale] = convert(fields)
        } else {
            fields.forEach { field, fields in
                (fields as? [String:AnyObject])?.forEach { locale, value in
                    if localizedFields[locale] == nil {
                        localizedFields[locale] = [String:Any]()
                    }

                    localizedFields[locale]?[field] = value
                }
            }
        }

        return try Entry(
            sys: (json => "sys") as! [String : AnyObject],
            localizedFields: localizedFields,

            identifier: json => "sys" => "id",
            type: json => "sys" => "type",
            locale: locale ?? DEFAULT_LOCALE
        )
    }
}

extension Field: Decodable {
    /// Decode JSON for a Field
    public static func decode(json: AnyObject) throws -> Field {
        var itemType: FieldType = .None
        if let itemTypeString = (try? json => "items" => "type") as? String {
            itemType = FieldType(rawValue: itemTypeString) ?? .None
        }
        if let itemTypeString = (try? json => "items" => "linkType") as? String {
            itemType = FieldType(rawValue: itemTypeString) ?? .None
        }
        if let linkTypeString = (try? json => "linkType") as? String {
            itemType = FieldType(rawValue: linkTypeString) ?? .None
        }

        return try Field(
            identifier: json => "id",
            name: json => "name",

            disabled: (try? json => "disabled") ?? false,
            localized: (try? json => "localized") ?? false,
            required: (try? json => "required") ?? false,

            type: FieldType(rawValue: try json => "type") ?? .None,
            itemType: itemType
        )
    }
}

extension Locale: Decodable {
    /// Decode JSON for a Locale
    public static func decode(json: AnyObject) throws -> Locale {
        return try Locale(
            code: json => "code",
            isDefault: json => "default",
            name: json => "name"
        )
    }
}

private extension Resource {
    static func decode(jsonIncludes: [String:AnyObject], inout _ includes: [String:Resource]) throws {
        let typename = "\(Self.self)"

        if let resources = jsonIncludes[typename] as? [[String:AnyObject]] {
            for resource in resources {
                let value = try self.decode(resource) as Resource
                includes[value.key] = value
            }
        }
    }

    var key: String { return "\(self.dynamicType)_\(self.identifier)" }
}

extension Space: Decodable {
    /// Decode JSON for a Space
    public static func decode(json: AnyObject) throws -> Space {
        return try Space(
            sys: (json => "sys") as! [String : AnyObject],

            identifier: json => "sys" => "id",
            locales: json => "locales",
            name: json => "name",
            type: json => "sys" => "type"
        )
    }
}
