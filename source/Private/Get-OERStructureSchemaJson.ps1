function Get-OERStructureSchemaJson {
    <#
    .SYNOPSIS
    Returns the JSON Schema (draft-07) for an Invoke-OERStructure apply document.

    .DESCRIPTION
    Produces the formal JSON Schema written into an Export-OERInventory bundle as schema.json, so an
    LLM (or any consumer) can validate a proposed apply document without access to the module. The
    schema mirrors the offline validator Test-OERStructureSchema exactly: the required top-level
    version key, the closed set of top-level keys, the per-section required fields, the enforced enums
    (catalog resource type, access review recurrence, role assignment principal type, eligibility accessType member/owner,
    membershipRuleProcessingState On/Paused (shared by administrative units and groups), activeEnablement
    and activationEnablement restricted to Justification/MultiFactorAuthentication/Ticketing) and the
    numeric ranges (eligibility durationDays 1-3650, pimPolicy/policy activationMaxHours 1-24, approval
    stage durationDays 1-365, escalationDays 1-365, assignment policy durationInDays 1-3650,
    durationInHours min 1, requestorSettings managerLevel min 1, approvalStage managerLevel min 1).
    Enum matching here is case-SENSITIVE, because that is what draft-07 specifies. The module is
    more forgiving: Test-OERStructureSchema accepts any casing and reports a Warning, and
    Read-OERStructureDocument rewrites the value to the canonical spelling declared here before the
    apply handlers build a request body. Resolve-OERStructureEnumCasing is the single owner of these
    canonical sets, and a unit test asserts that every enum declared below matches it exactly.
    approverInfoVisibility enum: Default/Visible/NotVisible. At most one of durationInDays/durationInHours/
    expirationDateTime may be set (documented; enforced by offline validator, not by draft-07). The
    pimPolicy block supports
    both the flat (member-only) form and the nested member/owner form -- a shared definitions entry
    (pimPolicyBlock) is referenced by both member and owner, keeping the schema DRY. A pimPolicy
    block, flat or nested, carries approval (requireApproval, approvers) with the same vocabulary as
    roleManagementPolicies: approvers is an object with optional users/groups string arrays resolved
    to object ids before the policy is compared, and requireApproval false takes precedence over a
    declared approvers block. Section item
    objects stay open (additionalProperties is not restricted); only the root object forbids unknown
    keys at the draft-07 level. Unknown keys in the roleAssignments and roleManagementPolicies sections,
    in a groups[] item, and in a groups[] pimPolicy block (root, or a nested member/owner block) stay
    schema-valid but are reported as a Warning by Test-OERStructureSchema, so a field the apply engine
    cannot honour is visible rather than silent; a pimPolicy key matching one of the five field names the
    inventory README used to document before they were renamed gets a did-you-mean hint pointing at its
    replacement. Tenant-dependent values that the
    offline validator does not enforce (role names, requestorScope scope strings) are intentionally
    left as free strings here and documented in the bundle prompt instead. Pure string builder: no
    Graph, ARM, or filesystem access. SharePointSite catalog resources carry the site URL in a
    distinct url field; name stays the human-readable site title. roleManagementPolicies items declare
    activation window and enablement, approval and approvers, authentication context, and eligible
    and active permanence plus day counts; notification rules are readable and writable through
    Get-/Set-OERRoleManagementPolicy but are not part of this schema and do not round-trip. The
    offline validator also enforces the ARM rule that requireMfaOnActivation and an authentication
    context are mutually exclusive, which draft-07 cannot express. accessReviews items declare the full set of
    fields the apply handler consumes -- reviewers and fallbackReviewers, both descriptions, the
    instance duration, the recurrence start/end/occurrences range, the five review settings booleans and
    defaultDecision (None/Approve/Deny/Recommendation) -- so a captured or hand-authored review is
    validated instead of silently stripped.
    Exactly three keys are typed [ "array", "null" ] rather than "array": groups[].members,
    administrativeUnits[].members and administrativeUnits[].scopedRoles. For those three an omitted
    key still reconciles and still PRUNES, so an explicit null is the only way a document can say
    "leave this collection alone" -- and it is what Get-OERInventory emits when the live read failed
    (issue #76). owners and eligibility are deliberately NOT widened: an omitted key is already
    hands-off for them, so nothing in the module produces a null there and a nullable type would be
    surface with no producer.
    accessReviews[].recurrence is nullable for the same reason on the scalar side: Test-OERStructureSchema
    treats an explicit null as undeclared and applies the OneTime default, so the schema must not reject
    what the module accepts. draft-07 applies "type" and "enum" INDEPENDENTLY -- both assert against the
    same instance -- so a nullable enum needs null in BOTH lists; widening only "type" still fails on the
    enum. Adding null to the enum does not loosen the string case: an out-of-set string and a non-string
    are still rejected. This is the ONLY enum in the schema carrying a null member, and the enum-ownership
    unit test strips it before comparing against Resolve-OERStructureEnumCasing, which owns the string
    values alone.

    .EXAMPLE
    Get-OERStructureSchemaJson
    Returns the draft-07 JSON Schema as a single string.

    .EXAMPLE
    Test-Json -Json (Get-Content ./proposal.json -Raw) -Schema (Get-OERStructureSchemaJson)
    Validates a proposed apply document against the schema.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param()

    @'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Omnicit.EntraRBAC structure document",
  "description": "Apply document accepted by Invoke-OERStructure / Test-OERStructure.",
  "type": "object",
  "additionalProperties": false,
  "required": [ "version" ],
  "definitions": {
    "pimPolicyBlock": {
      "type": "object",
      "properties": {
        "activationMaxHours": { "type": "integer", "minimum": 1, "maximum": 24 },
        "authenticationContextId": { "type": [ "string", "null" ] },
        "activationEnablement": { "type": "array", "items": { "type": "string", "enum": [ "Justification", "MultiFactorAuthentication", "Ticketing" ] } },
        "allowPermanentEligibility": { "type": "boolean" },
        "eligibleDurationDays": { "type": "integer", "minimum": 1, "maximum": 3650 },
        "allowPermanentActive": { "type": "boolean" },
        "activeDurationDays": { "type": "integer", "minimum": 1, "maximum": 3650 },
        "activeEnablement": { "type": "array", "items": { "type": "string", "enum": [ "Justification", "MultiFactorAuthentication", "Ticketing" ] } },
        "notifications": {
          "type": "object",
          "properties": {
            "eligibleAlert": { "type": "array", "items": { "type": "string" } },
            "activeAlert": { "type": "array", "items": { "type": "string" } },
            "activationAlert": { "type": "array", "items": { "type": "string" } }
          }
        },
        "requireApproval": { "type": "boolean" },
        "approvers": {
          "type": "object",
          "description": "Approvers of an activation when approval is required: users are user principal names or object ids, groups are group display names or object ids; each is resolved to an object id before the policy is compared. Declaring one side leaves the other side on the live policy untouched. requireApproval false TAKES PRECEDENCE: approvers declared alongside it are ignored, and the offline validator warns about the combination.",
          "properties": {
            "users": { "type": "array", "items": { "type": "string" } },
            "groups": { "type": "array", "items": { "type": "string" } }
          }
        }
      }
    }
  },
  "properties": {
    "version": { "type": "string", "minLength": 1 },
    "tenantAlias": { "type": "string" },
    "groups": {
      "type": "array",
      "description": "Entra ID groups. displayName is the match key: an existing group is matched and updated by it. Renaming through the document is not possible -- changing displayName creates a new group and leaves the old one in place, unreported.",
      "items": {
        "type": "object",
        "oneOf": [
          { "required": [ "displayName" ], "not": { "required": [ "template" ] } },
          { "required": [ "template", "tokens" ], "not": { "required": [ "displayName" ] } }
        ],
        "properties": {
          "displayName": { "type": "string" },
          "template": { "type": "string" },
          "tokens": { "type": "object" },
          "roleAssignable": { "type": "boolean" },
          "dynamic": { "type": "boolean" },
          "description": { "type": [ "string", "null" ] },
          "membershipRule": { "type": "string" },
          "membershipRuleProcessingState": { "type": "string", "enum": [ "On", "Paused" ] },
          "mailNickname": { "type": "string" },
          "administrativeUnit": {
            "type": "string",
            "description": "Administrative unit (display name or id) the group is created in. Create-only: it is applied when the group is created and is not captured by Get-OERInventory, so it never round-trips. Because of that, the SAME document's administrativeUnits[] entry whose displayName matches this value must also list this group's displayName in its own members array -- otherwise the administrativeUnits section of the SAME apply run (it is dispatched after groups) sees the group as an undeclared member of that unit and -Prune removes the membership the create just added, and every later apply does the same, since nothing re-applies this create-only field to self-heal it."
          },
          "members": {
            "type": [ "array", "null" ],
            "items": { "type": "string" },
            "description": "An omitted key still reconciles: existing members it does not name are removed under -Prune (or reported Extra without it). An explicit null leaves membership untouched entirely -- null, not an omitted key, is how a group is declared without touching its members. [] reconciles to no declared members. Get-OERInventory emits null here when the live read failed."
          },
          "owners": {
            "type": "array",
            "items": { "type": "string" },
            "description": "Reconciled only when declared and non-null: an omitted OR explicit null owners key is never reconciled or pruned (unlike members, where only null skips it). [] reconciles to no declared owners."
          },
          "eligibility": {
            "type": "array",
            "description": "Reconciled only when declared and non-null: an omitted OR explicit null eligibility key is never reconciled or pruned, because eligibility is standing privileged access and must not be revoked by a document that never mentioned it. [] reconciles to no declared eligibility.",
            "items": {
              "type": "object",
              "required": [ "principal" ],
              "properties": {
                "principal": { "type": "string" },
                "accessType": { "type": "string", "enum": [ "member", "owner" ] },
                "durationDays": { "type": "integer", "minimum": 1, "maximum": 3650 }
              }
            }
          },
          "pimPolicy": {
            "type": "object",
            "properties": {
              "activationMaxHours": { "type": "integer", "minimum": 1, "maximum": 24 },
              "authenticationContextId": { "type": [ "string", "null" ] },
              "activationEnablement": { "type": "array", "items": { "type": "string", "enum": [ "Justification", "MultiFactorAuthentication", "Ticketing" ] } },
              "allowPermanentEligibility": { "type": "boolean" },
              "eligibleDurationDays": { "type": "integer", "minimum": 1, "maximum": 3650 },
              "allowPermanentActive": { "type": "boolean" },
              "activeDurationDays": { "type": "integer", "minimum": 1, "maximum": 3650 },
              "activeEnablement": { "type": "array", "items": { "type": "string", "enum": [ "Justification", "MultiFactorAuthentication", "Ticketing" ] } },
              "notifications": {
                "type": "object",
                "properties": {
                  "eligibleAlert": { "type": "array", "items": { "type": "string" } },
                  "activeAlert": { "type": "array", "items": { "type": "string" } },
                  "activationAlert": { "type": "array", "items": { "type": "string" } }
                }
              },
              "requireApproval": { "type": "boolean" },
              "approvers": {
                "type": "object",
                "description": "Approvers of an activation when approval is required: users are user principal names or object ids, groups are group display names or object ids; each is resolved to an object id before the policy is compared. Declaring one side leaves the other side on the live policy untouched. requireApproval false TAKES PRECEDENCE: approvers declared alongside it are ignored, and the offline validator warns about the combination.",
                "properties": {
                  "users": { "type": "array", "items": { "type": "string" } },
                  "groups": { "type": "array", "items": { "type": "string" } }
                }
              },
              "member": { "$ref": "#/definitions/pimPolicyBlock" },
              "owner": { "$ref": "#/definitions/pimPolicyBlock" }
            }
          }
        }
      }
    },
    "administrativeUnits": {
      "type": "array",
      "description": "Administrative units. displayName is the match key: an existing unit is matched and updated by it. Renaming through the document is not possible -- changing displayName creates a new unit and leaves the old one in place, unreported.",
      "items": {
        "type": "object",
        "required": [ "displayName" ],
        "properties": {
          "displayName": { "type": "string" },
          "description": { "type": [ "string", "null" ] },
          "restricted": { "type": "boolean" },
          "dynamic": { "type": "boolean" },
          "membershipRule": { "type": "string" },
          "membershipRuleProcessingState": { "type": "string", "enum": [ "On", "Paused" ] },
          "hiddenMembership": { "type": "boolean" },
          "members": {
            "type": [ "array", "null" ],
            "items": { "type": "string" },
            "description": "An omitted key still reconciles: existing members it does not name are removed under -Prune (or reported Extra without it). An explicit null leaves membership untouched entirely -- null, not an omitted key, is how a unit is declared without touching its members. [] reconciles to no declared members. Get-OERInventory emits null here when the live read failed."
          },
          "scopedRoles": {
            "type": [ "array", "null" ],
            "description": "An omitted key still reconciles: existing scoped roles it does not name are removed under -Prune (or reported Extra without it). An explicit null leaves scoped roles untouched entirely -- null, not an omitted key, is how a unit is declared without touching its scoped roles. [] reconciles to no declared scoped roles. Get-OERInventory emits null here when the live read failed.",
            "items": {
              "type": "object",
              "required": [ "role", "principal" ],
              "properties": {
                "role": { "type": "string" },
                "principal": { "type": "string" }
              }
            }
          }
        }
      }
    },
    "catalogs": {
      "type": "array",
      "description": "Entitlement Management catalogs. displayName is the match key: an existing catalog is matched and updated by it. Renaming through the document is not possible -- changing displayName creates a new catalog and leaves the old one in place, unreported.",
      "items": {
        "type": "object",
        "required": [ "displayName" ],
        "properties": {
          "displayName": { "type": "string" },
          "description": { "type": [ "string", "null" ] },
          "externallyVisible": {
            "type": "boolean",
            "description": "Whether the catalog's access packages are requestable by users outside the directory (connected-organization users)."
          },
          "resources": {
            "type": "array",
            "description": "An omitted key still reconciles: existing resources it does not name are removed under -Prune (or reported Extra without it). An explicit null leaves resources untouched entirely -- null, not an omitted key, is how a catalog is declared without touching its resources. [] reconciles to no declared resources.",
            "items": {
              "type": "object",
              "required": [ "name" ],
              "properties": {
                "name": { "type": "string" },
                "type": { "type": "string", "enum": [ "Group", "Application", "SharePointSite" ] },
                "url": {
                  "type": "string",
                  "description": "SharePoint Online site URL. Strongly recommended for a SharePointSite resource: the site is onboarded by URL (the resource originId). When url is omitted the apply falls back to name, which works only when name is itself a site URL; the offline validator warns when neither is a URL. Ignored for Group and Application resources."
                }
              }
            }
          }
        }
      }
    },
    "accessPackages": {
      "type": "array",
      "description": "Entitlement Management access packages. displayName is the match key within the declared catalog (names are unique per catalog, not tenant-wide): an existing package is matched and updated by it. Renaming through the document is not possible -- changing displayName creates a new package and leaves the old one in place, unreported; there is no top-level Extra reporting for this section either.",
      "items": {
        "type": "object",
        "required": [ "displayName", "catalog" ],
        "properties": {
          "displayName": { "type": "string" },
          "catalog": { "type": "string" },
          "description": { "type": [ "string", "null" ] },
          "hidden": { "type": "boolean" },
          "resourceRoles": {
            "type": "array",
            "description": "An omitted key still reconciles: existing bindings it does not name are removed under -Prune (or reported Extra without it). An explicit null leaves bindings untouched entirely -- null, not an omitted key, is how a package is declared without touching its resource role bindings. [] reconciles to no declared bindings.",
            "items": {
              "type": "object",
              "required": [ "resource", "role" ],
              "properties": {
                "resource": { "type": "string" },
                "role": { "type": "string" }
              }
            }
          },
          "assignmentPolicies": {
            "type": "array",
            "items": {
              "type": "object",
              "required": [ "displayName" ],
              "properties": {
                "displayName": { "type": "string" },
                "description": { "type": [ "string", "null" ] },
                "requestorScope": {
                  "type": "object",
                  "description": "An explicit scope always wins. When scope is omitted but users or groups is a non-empty array, Invoke-OERStructure infers scope as SpecificDirectoryUsers rather than falling back to the AllMemberUsers default, which would have discarded the users/groups (issue #69). That fallback was never applied to a tenant: Test-OERStructureSchema previously raised an Error for the shape and Invoke-OERStructure refuses any document with one, so the change is that such a document is now accepted -- Test-OERStructureSchema reports it as a Warning, not an Error, and recommends declaring scope explicitly instead of relying on the inference. scope is therefore NOT a required key here: a document that omits it is schema-valid, matching the module's own offline validator.",
                  "properties": {
                    "scope": { "type": "string", "minLength": 1 },
                    "users": { "type": "array", "items": { "type": "string" } },
                    "groups": { "type": "array", "items": { "type": "string" } }
                  }
                },
                "requestorSettings": {
                  "type": "object",
                  "properties": {
                    "allowSelfRequest": { "type": "boolean" },
                    "allowManagerRequest": { "type": "boolean" },
                    "managerLevel": { "type": "integer", "minimum": 1 },
                    "allowCustomSchedule": { "type": "boolean" },
                    "allowSelfExtend": { "type": "boolean" },
                    "allowSelfRemove": { "type": "boolean" },
                    "allowOnBehalfUpdate": { "type": "boolean" },
                    "allowOnBehalfRemove": { "type": "boolean" }
                  }
                },
                "requireApproval": { "type": "boolean" },
                "requireRequestorJustification": { "type": "boolean" },
                "requireApprovalForUpdate": { "type": "boolean" },
                "notificationsDisabled": { "type": "boolean" },
                "approvalStages": {
                  "type": "array",
                  "description": "fallbackUsers/fallbackGroups cover only the PRIMARY approver's fallback. A stage is always rebuilt as a whole on update, so any escalation-approver fallback set through the portal (fallbackEscalationApprovers, not modelled here) is cleared the next time this stage is reconciled -- it is a loss, not a carve-out. A declared-empty [] CLEARS every live approval stage; never pair it with requireApproval true.",
                  "items": {
                    "type": "object",
                    "properties": {
                      "durationDays": { "type": "integer", "minimum": 1, "maximum": 365 },
                      "manager": { "type": "boolean" },
                      "managerLevel": { "type": "integer", "minimum": 1 },
                      "users": { "type": "array", "items": { "type": "string" } },
                      "groups": { "type": "array", "items": { "type": "string" } },
                      "alternateUsers": { "type": "array", "items": { "type": "string" } },
                      "alternateGroups": { "type": "array", "items": { "type": "string" } },
                      "fallbackUsers": { "type": "array", "items": { "type": "string" } },
                      "fallbackGroups": { "type": "array", "items": { "type": "string" } },
                      "internalSponsor": { "type": "boolean" },
                      "externalSponsor": { "type": "boolean" },
                      "requireApproverJustification": { "type": "boolean" },
                      "escalationDays": { "type": "integer", "minimum": 1, "maximum": 365 },
                      "approverInfoVisibility": { "type": "string", "enum": [ "Default", "Visible", "NotVisible" ] }
                    }
                  }
                },
                "durationInDays": { "type": "integer", "minimum": 1, "maximum": 3650 },
                "durationInHours": { "type": "integer", "minimum": 1 },
                "expirationDateTime": {
                  "type": "string",
                  "description": "ISO 8601 date-time string. At most one of durationInDays/durationInHours/expirationDateTime may be set; the offline validator enforces mutual exclusion -- draft-07 cannot express it cleanly."
                }
              }
            }
          }
        }
      }
    },
    "accessReviews": {
      "type": "array",
      "description": "Access review series. displayName is the match key: an existing review is updated in place through a full-object PUT (read-modify-write), so every writable property the module models or explicitly carries forward is preserved. A writable top-level property added to the Microsoft Graph accessReviewScheduleDefinition resource in future and not yet modelled here would be dropped by that PUT.",
      "items": {
        "type": "object",
        "required": [ "displayName", "accessPackage", "assignmentPolicy" ],
        "properties": {
          "displayName": { "type": "string" },
          "accessPackage": { "type": "string" },
          "assignmentPolicy": { "type": "string" },
          "recurrence": {
            "type": [ "string", "null" ],
            "enum": [ "OneTime", "Weekly", "Monthly", "Quarterly", "Annually", null ],
            "description": "An explicit null means a one-time review, exactly as omitting the key does -- the offline validator treats a null as undeclared and applies the OneTime default. null appears in both type and enum because draft-07 asserts them independently."
          },
          "startDate": { "type": "string", "description": "ISO 8601 date or date-time the first review instance starts. Defaults to today when omitted." },
          "endDate": { "type": "string", "description": "ISO 8601 date the recurrence series ends. Mutually exclusive with occurrences; ignored for a OneTime review." },
          "occurrences": { "type": "integer", "minimum": 1, "description": "Number of review instances in the series. Mutually exclusive with endDate; ignored for a OneTime review." },
          "durationInDays": { "type": "integer", "minimum": 1, "maximum": 365 },
          "reviewers": { "type": "array", "items": { "type": "string" }, "description": "Reviewer tokens: 'manager', 'self', a user principal name, or a group display name or id. Defaults to manager (which then requires fallbackReviewers). A declared-empty [] is a SELF review, not the manager default." },
          "fallbackReviewers": { "type": "array", "items": { "type": "string" }, "description": "Fallback reviewer user principal names, or group display names or ids. Required by Microsoft Graph whenever manager is a reviewer; a declared-empty [] does not satisfy that." },
          "descriptionForAdmins": { "type": "string" },
          "descriptionForReviewers": { "type": "string" },
          "mailNotification": { "type": "boolean" },
          "reminderNotification": { "type": "boolean" },
          "requireJustification": { "type": "boolean" },
          "recommendationsEnabled": { "type": "boolean" },
          "autoApplyDecisions": { "type": "boolean" },
          "defaultDecision": { "type": "string", "enum": [ "None", "Approve", "Deny", "Recommendation" ] }
        }
      }
    },
    "roleAssignments": {
      "type": "array",
      "items": {
        "type": "object",
        "required": [ "scope", "role", "principal" ],
        "properties": {
          "scope": { "type": "string" },
          "role": { "type": "string" },
          "principal": { "type": "string" },
          "principalType": { "type": "string", "enum": [ "User", "Group", "ServicePrincipal" ] },
          "description": { "type": "string" },
          "condition": { "type": "string" },
          "conditionVersion": { "type": "string" }
        }
      }
    },
    "roleManagementPolicies": {
      "type": "array",
      "items": {
        "type": "object",
        "required": [ "scope", "role" ],
        "properties": {
          "scope": { "type": "string" },
          "role": { "type": "string" },
          "allowPermanentEligibility": { "type": "boolean" },
          "eligibleDurationDays": { "type": "integer", "minimum": 1, "maximum": 3650 },
          "allowPermanentActiveAssignment": { "type": "boolean" },
          "activeDurationDays": { "type": "integer", "minimum": 1, "maximum": 3650 },
          "activationMaxHours": { "type": "integer", "minimum": 1, "maximum": 24 },
          "requireMfaOnActivation": { "type": "boolean" },
          "requireJustificationOnActivation": { "type": "boolean" },
          "requireTicketOnActivation": { "type": "boolean" },
          "requireApproval": { "type": "boolean" },
          "approvers": {
            "type": "object",
            "description": "Approvers applied when approval is required. requireApproval false TAKES PRECEDENCE: declaring approvers alongside requireApproval false leaves the approvers unapplied (Azure Resource Manager turns approval back on whenever approvers are written), and the offline validator warns about the combination.",
            "properties": {
              "users": { "type": "array", "items": { "type": "string" } },
              "groups": { "type": "array", "items": { "type": "string" } }
            }
          },
          "authenticationContextId": {
            "type": [ "string", "null" ],
            "description": "Authentication context claim value required on activation, for example c1. An empty string DISABLES the authentication context. An explicit null means NOT DECLARED -- the live setting is left untouched, the same as omitting the key. Mutually exclusive with requireMfaOnActivation true -- Azure PIM rejects both at once."
          },
          "requireMfaOnActiveAssignment": { "type": "boolean" },
          "requireJustificationOnActiveAssignment": { "type": "boolean" }
        }
      }
    }
  }
}
'@
}
