# Contributing to Smart Record Cloner

Thank you for your interest in improving Smart Record Cloner!

## Local Development Workflow
1. Authorize your Dev Hub:
   ```bash
   sf org login web -d -a my-dev-hub
   ```
2. Create a scratch org:
   ```bash
   sf org create scratch -f config/project-scratch-def.json -a cloner-dev -d 7
   ```
3. Push metadata:
   ```bash
   sf project deploy start
   ```
4. Run Apex & LWC tests:
   ```bash
   sf apex run test -c -r human
   npm run test:unit
   ```

## PR Requirements
- High test coverage (>85%) on all Apex controllers and services.
- Clean bulk-safe operations (no SOQL/DML in loops).
- SLDS-compliant LWC UI styling.
