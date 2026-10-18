function Get-OERNamingStandardSchemaJson {
    <#
    .SYNOPSIS
    Returns the JSON Schema (draft-07) for a naming standard file.

    .DESCRIPTION
    Produces the formal JSON Schema for the file Test-OERStructure -NamingStandard reads, so an
    operator, an editor or an LLM can validate a naming standard without the module. The schema
    mirrors the reader Read-OERNamingStandard: the required version (exactly 1.0), separator,
    sections and segments keys, the closed set of root and segment keys (additionalProperties false at
    both levels), the six section names Test-OERStructure can check (groups, administrativeUnits,
    catalogs, accessPackages, assignmentPolicies, accessReviews), the four letter cases (PascalCase,
    camelCase, UPPERCASE, lowercase), a maxLength of 1 to 256, and the rule that a segment names a
    closed list of values or a pattern but never both. Enum matching is case-SENSITIVE, which is what
    draft-07 specifies and what the reader enforces.

    Two rules draft-07 cannot express are enforced by the reader alone: every pattern and every
    exceptions entry must compile as a .NET regular expression, and no values entry may contain the
    separator, since such a value could never match a segment. The descriptions of pattern, exceptions,
    values and case state the matching semantics in one sentence each; the reference list of the
    semantics is the help of Test-OERNamingStandardName. Pure string builder: no Graph, ARM, or
    filesystem access.

    .EXAMPLE
    Test-Json -Json (Get-Content ./naming-standard.json -Raw) -Schema (Get-OERNamingStandardSchemaJson)
    Validates a naming standard file against the schema.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param()

    @'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Omnicit.EntraRBAC naming standard",
  "description": "Naming standard read by Test-OERStructure -NamingStandard. A name is split at the separator into segments, and each segment is checked against its entry in segments. The check is advisory: a name that breaks the standard is a Warning, never an Error.",
  "type": "object",
  "additionalProperties": false,
  "required": [ "version", "separator", "sections", "segments" ],
  "properties": {
    "$schema": { "type": "string", "description": "Optional reference to this schema, for editor support." },
    "version": { "type": "string", "enum": [ "1.0" ], "description": "The file format version. Exactly 1.0." },
    "description": { "type": "string", "description": "Free text describing the standard. Not used by the check." },
    "separator": { "type": "string", "minLength": 1, "description": "The text that separates the segments of a name. It is compared as written, never as a pattern." },
    "maxLength": { "type": "integer", "minimum": 1, "maximum": 256, "description": "The longest name allowed, in characters. Omit it for no limit." },
    "sections": {
      "type": "array",
      "minItems": 1,
      "uniqueItems": true,
      "description": "The document sections the standard applies to. assignmentPolicies are the policies of the accessPackages entries.",
      "items": { "type": "string", "enum": [ "groups", "administrativeUnits", "catalogs", "accessPackages", "assignmentPolicies", "accessReviews" ] }
    },
    "includeSyncedGroups": { "type": "boolean", "default": false, "description": "When true, a group synchronized from on-premises (onPremisesSynced true) is checked too. By default it is skipped, since Invoke-OERStructure writes nothing to it." },
    "segments": {
      "type": "array",
      "minItems": 1,
      "description": "The ordered segments of a name. A segment with optional true may be left out; the segments that are present keep this order.",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [ "name" ],
        "not": { "required": [ "values", "pattern" ] },
        "properties": {
          "name": { "type": "string", "minLength": 1, "description": "The segment's name, used in findings." },
          "description": { "type": "string", "description": "Free text describing the segment. Not used by the check." },
          "values": {
            "type": "array",
            "minItems": 1,
            "uniqueItems": true,
            "description": "A closed list of the allowed values, compared as exact, case-sensitive text and never as patterns. No value may contain the separator. Use values or pattern, not both.",
            "items": { "type": "string", "minLength": 1 }
          },
          "pattern": { "type": "string", "minLength": 1, "description": "A .NET regular expression the whole segment must match (it is anchored at both ends, so Fin does not match Finance), case-sensitive unless it starts with (?i). Use values or pattern, not both." },
          "case": { "type": "string", "enum": [ "PascalCase", "camelCase", "UPPERCASE", "lowercase" ], "description": "The letter case of the segment: PascalCase is an uppercase letter first and then only letters and digits, camelCase a lowercase letter first and then only letters and digits, UPPERCASE no lowercase letter, lowercase no uppercase letter. Omit it to allow any case." },
          "optional": { "type": "boolean", "default": false, "description": "When true, the segment may be left out of a name." }
        }
      }
    },
    "exceptions": {
      "type": "array",
      "description": "Names that keep their names: a name that matches one of these .NET regular expressions in full (anchored at both ends, so All Users does not exempt All Users Copy; case-sensitive unless the entry starts with (?i)) is never checked.",
      "items": { "type": "string", "minLength": 1 }
    }
  }
}
'@
}
