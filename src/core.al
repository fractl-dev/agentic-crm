module agenticcrm.core

record ContactInfo {
    contactEmail String,
    firstName String,
    lastName String,
    meetingTitle String,
    meetingBody String,
    meetingDate String
}

record ContactSearchResult {
    contactFound Boolean,
    existingContactId String @optional
}

record ContactResult {
    finalContactId String
}

record OwnerResult {
    ownerId String @optional
}

event FindContactByEmail {
    email String
}

workflow FindContactByEmail {
    console.log("=== FindContactByEmail: Searching for: " + FindContactByEmail.email);
    {hubspot/Contact {email? FindContactByEmail.email}} @as foundContacts;
    console.log("=== FindContactByEmail: Found " + foundContacts.length + " contacts");

    if (foundContacts.length > 0) {
        foundContacts @as [firstContact];
        console.log("=== FindContactByEmail: Contact exists - ID: " + firstContact.id);
        {ContactSearchResult {
            contactFound true,
            existingContactId firstContact.id
        }}
    } else {
        console.log("=== FindContactByEmail: No contact found, will create new");
        {ContactSearchResult {
            contactFound false
        }}
    }
}

event FindOwnerByEmail {
    email String
}

workflow FindOwnerByEmail {
    console.log("=== FindOwnerByEmail: Searching for: " + FindOwnerByEmail.email);
    {hubspot/Owner {email? FindOwnerByEmail.email}} @as foundOwners;
    console.log("=== FindOwnerByEmail: Found " + foundOwners.length + " owners");

    if (foundOwners.length > 0) {
        foundOwners @as [firstOwner];
        console.log("=== FindOwnerByEmail: Owner exists - ID: " + firstOwner.id);
        {OwnerResult {
            ownerId firstOwner.id
        }}
    } else {
        console.log("=== FindOwnerByEmail: No owner found, returning null");
        {OwnerResult {
            ownerId null
        }}
    }
}

@public agent parseEmailInfo {
  llm "llm01",
  role "Extract contact and meeting information from the gmail/Email instance."
  instruction "You have access to {{message}} which contains a gmail/Email instance.

The {{message}} structure is a JSON object with an 'attributes' field containing:
- sender: string like 'Name <email@domain.com>'
- recipients: string like 'Name <email@domain.com>'
- subject: the email subject line
- body: the email body content
- date: ISO 8601 timestamp

YOUR TASK: Parse {{message}} and extract the following information:

STEP 1: Find sender and recipients
From {{message}}, locate the sender field and recipients field.
Example: if sender is 'Pratik Karki <pratik@fractl.io>', that's the sender text.

STEP 2: Determine which contact to extract
IF sender contains 'pratik@fractl.io' THEN use recipients for contact extraction
ELSE use sender for contact extraction

STEP 3: Extract contact information from chosen text
From the chosen text (sender or recipients):
- contactEmail = extract EXACTLY the email address between < and >
- firstName = extract the first word before <
- lastName = extract the second word before <

STEP 4: Extract meeting title
meetingTitle = copy the EXACT value from the subject field in {{message}}

STEP 5: Summarize meeting body
Read the body field from {{message}} and write a brief summary.
meetingBody = your summary of the body content

STEP 6: Extract meeting date
meetingDate = copy the EXACT value from the date field in {{message}}

CRITICAL RULES:
- Parse the actual {{message}} you receive, not examples
- Email addresses must be copied EXACTLY as they appear between < and >
- Do NOT modify domains or email addresses
- The date must be copied EXACTLY in ISO 8601 format
- All data comes from {{message}}, not from your knowledge

EXAMPLE (for format reference only - use your actual {{message}}):
If {{message}} contains:
{
  \"attributes\": {
    \"sender\": \"John Doe <john@company.io>\",
    \"recipients\": \"Pratik Karki <pratik@fractl.io>\",
    \"subject\": \"Project Review Meeting\",
    \"body\": \"Let's discuss the project status and timeline.\",
    \"date\": \"2025-12-31T10:30:00.000Z\"
  }
}

You would extract:
{
  \"contactEmail\": \"john@company.io\",
  \"firstName\": \"John\",
  \"lastName\": \"Doe\",
  \"meetingTitle\": \"Project Review Meeting\",
  \"meetingBody\": \"Discussion about project status and timeline\",
  \"meetingDate\": \"2025-12-31T10:30:00.000Z\"
}",
  responseSchema agenticcrm.core/ContactInfo,
  retry classifyRetry
}

@public agent findExistingContact {
  llm "llm01",
  role "Search for contact in HubSpot."
  instruction "You have available: {{contactEmail}}

Call agenticcrm.core/FindContactByEmail with email={{contactEmail}}

Return the ContactSearchResult that the tool provides.",
  responseSchema agenticcrm.core/ContactSearchResult,
  retry classifyRetry,
  tools [agenticcrm.core/FindContactByEmail]
}

decision contactExistsCheck {
  case (contactFound == true) {
    ContactExists
  }
  case (contactFound == false) {
    ContactNotFound
  }
}

@public agent updateExistingContact {
  llm "llm01",
  role "Return the existing contact ID."
  instruction "You have available: {{existingContactId}}

Return this exact JSON structure:
{
  \"finalContactId\": \"{{existingContactId}}\"
}

Replace {{existingContactId}} with the actual ID value from your scratchpad.",
  responseSchema agenticcrm.core/ContactResult,
  retry classifyRetry,
  tools [hubspot/Contact]
}

@public agent createNewContact {
  llm "llm01",
  role "Create a new contact in HubSpot."
  instruction "You have available:
- {{contactEmail}}
- {{firstName}}
- {{lastName}}

STEP 1: Create the contact
Use the hubspot/Contact tool to create a contact with:
- email: the EXACT value from {{contactEmail}}
- first_name: the EXACT value from {{firstName}}
- last_name: the EXACT value from {{lastName}}

STEP 2: Extract and return the ID
The tool returns an object with an id field.
Return JSON: {\"finalContactId\": \"<the id value>\"}

EXAMPLE:
If contactEmail=\"ranga@fractl.io\", firstName=\"Ranga\", lastName=\"Rao\":
Tool creates contact, returns id \"350155650790\"
You return: {\"finalContactId\": \"350155650790\"}

CRITICAL GUARDRAILS:
- Use the EXACT email from {{contactEmail}} - do not change the domain
- Use the EXACT firstName from {{firstName}} - do not modify it
- Use the EXACT lastName from {{lastName}} - do not modify it",
  responseSchema agenticcrm.core/ContactResult,
  retry classifyRetry,
  tools [hubspot/Contact]
}

@public agent findOwner {
  llm "llm01",
  role "Find the HubSpot owner."
  instruction "Step 1: Call the tool agenticcrm.core/FindOwnerByEmail
Pass: email = pratik@fractl.io

Step 2: The tool returns an OwnerResult with an ownerId field
Return exactly what the tool returned.",
  responseSchema agenticcrm.core/OwnerResult,
  retry classifyRetry,
  tools [agenticcrm.core/FindOwnerByEmail]
}

@public agent createMeeting {
  llm "llm01",
  role "Create a meeting in HubSpot with all required fields."
  instruction "Create a meeting in HubSpot using the hubspot/Meeting tool.

YOU HAVE AVAILABLE:
- {{finalContactId}} - the contact ID to associate
- {{meetingTitle}} - the meeting title
- {{meetingBody}} - the meeting summary
- {{meetingDate}} - the email date in ISO 8601 format (e.g., '2025-12-31T05:02:35.000Z')
- {{ownerId}} - the owner ID (may be null)

STEP 1: Determine owner ID
If {{ownerId}} is null or not a valid integer, use \"85257652\"
Otherwise use the value from {{ownerId}}

STEP 2: Convert email date to Unix timestamp
Take the ISO 8601 date from {{meetingDate}} (e.g., '2025-12-31T05:02:35.000Z')
Convert it to Unix timestamp in milliseconds.
Example: '2025-12-31T05:02:35.000Z' converts to 1735620155000

STEP 3: Calculate end time
Add 3600000 milliseconds (1 hour) to the timestamp.
Example: 1735620155000 + 3600000 = 1735623755000

STEP 4: Use the hubspot/Meeting tool with ALL these fields:
- meeting_title: EXACT value from {{meetingTitle}}
- meeting_body: EXACT value from {{meetingBody}}
- timestamp: the Unix milliseconds timestamp from the email date
- meeting_outcome: exactly \"COMPLETED\"
- meeting_start_time: the Unix milliseconds timestamp from the email date
- meeting_end_time: the timestamp + 3600000
- owner: the owner ID from STEP 1
- associated_contacts: EXACT value from {{finalContactId}}

EXAMPLE:
Input values:
- meetingTitle = \"API Integration Planning\"
- meetingBody = \"Discussed REST API architecture and timeline\"
- meetingDate = \"2025-12-31T05:02:35.000Z\"
- finalContactId = \"350155650790\"
- ownerId = null
- Converted timestamp = 1735620155000

You call the tool with:
- meeting_title: \"API Integration Planning\"
- meeting_body: \"Discussed REST API architecture and timeline\"
- timestamp: \"1735620155000\"
- meeting_outcome: \"COMPLETED\"
- meeting_start_time: \"1735620155000\"
- meeting_end_time: \"1735623755000\"
- owner: \"85257652\"
- associated_contacts: \"350155650790\"

CRITICAL GUARDRAILS:
- Convert the ISO 8601 date from {{meetingDate}} to Unix milliseconds
- Use EXACT values from {{variables}} - do not modify
- All timestamps must be Unix milliseconds as strings
- Always provide owner field using fallback 85257652 if needed",
  retry classifyRetry,
  tools [hubspot/Meeting]
}

flow crmManager {
  parseEmailInfo --> findExistingContact
  findExistingContact --> contactExistsCheck
  contactExistsCheck --> "ContactExists" updateExistingContact
  contactExistsCheck --> "ContactNotFound" createNewContact
  updateExistingContact --> findOwner
  createNewContact --> findOwner
  findOwner --> createMeeting
}

@public agent crmManager {
  role "You coordinate the complete CRM workflow: extract contact and meeting information from the email, find or create the contact in HubSpot, find the owner, and create the meeting with proper associations."
}

workflow @after create:gmail/Email {
    console.log("Following data arrived of instance: ", gmail/Email);

    {crmManager {message gmail/Email}}
}
