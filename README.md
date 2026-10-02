# Smart Record Cloner (Deep Clone Utility)

> **Open-Source (MIT)** | Built for the Trailblazer & Salesforce Developer Community | Open for PRs & Discussions

## 1. Overview & Vision
A 100% free, zero-friction open-source Salesforce AppExchange utility that solves one of the oldest pain points in Salesforce: **cloning records along with their related child lists (related objects) in a single click**.

Standard Salesforce has a basic "Clone" button, but it only clones the parent record (e.g., Opportunity without OpportunityLineItems, Quote without QuoteLineItems, Account without Contacts). Third-party solutions are either clunky, abandoned, or cost $50–$200/month.

## 2. Core Features (MVP)
- **Deep Clone Engine (Apex):**
  - Clones parent record and dynamically retrieves child relationships via describe metadata (`Schema.DescribeSObjectResult`).
  - Customizable field stripping (e.g., clears `Id`, `CreatedDate`, reset statuses like `StageName = 'Prospecting'`).
- **Lightning Web Component (LWC) Modal:**
  - Placed on any record page as a Quick Action button (`Clone with Related`).
  - Interactive UI: Checkboxes to select which child lists to copy (e.g., "[x] Copy Products (4)", "[ ] Copy Notes (2)").
  - Option to set new parent record name or adjust key fields before saving.
- **Bulk Safe & Governor Limit Compliant:**
  - Handles 200+ child records cleanly with efficient DML and single transaction execution.

## 3. Architecture & Tech Stack
- **Frontend:** Lightning Web Components (LWC), SLDS (Salesforce Lightning Design System).
- **Backend:** Apex (`DeepCloneController.cls`, `DeepCloneService.cls`).
- **Packaging:** Salesforce 2GP (Second-Generation Managed Package) or Unlocked Package for AppExchange.
- **Permissions:** Permission set `Smart_Record_Cloner_User` granting Apex access.

## 4. AppExchange & Community Strategy
- **Positioning:** "100% Free Forever - No limits, No credit card".
- **Review Hook:** Post-clone celebration banner with an unobtrusive link: *"Saved you 15 minutes? Drop us a 5-star review on AppExchange!"*
- **Viral Expansion:** Every sales or operations rep using it recommends it to their Salesforce Admin.

## 5. Open-Source Roadmap & Good First Issues for PRs
- [ ] Add support for custom object deep cloning via dynamic metadata.
- [ ] Field-mapping overrides (allow admins to preset default values for cloned children).
- [ ] Flow Invocable Action variant for deep cloning records from headless flows.
- [ ] Internationalization (i18n) custom labels for community translations.
