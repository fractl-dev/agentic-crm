module agenticcrm.core

{agentlang.ai/LLM {
    name "llm01",
    service "openai",
    config
    {"model": "gpt-5.2"}
}, @upsert}

agentlang/retry classifyRetry {
  attempts 3,
  backoff {
    strategy linear,
    delay 2,
    magnitude seconds,
    factor 2
  }
}

event findContact {
  email String,
  first_name String,
  last_name String,
  @meta {"documentation": "Find the return proper hubspot contact based on email, first_name and last_name."}
}

workflow findContact {
  {hubspot/Contact {
      email? findContact.email,
      first_name findContact.first_name,
      last_name findContact.last_name
    }} @as [c];
  c
}

@public agent emailExtractorAgent {
  llm "llm01",
  role "You are an AI assistant responsible for extracting contact information from Gmail emails and managing HubSpot contacts."
  instruction "Your task is to process email information, manage HubSpot contacts, and RETURN the contact information for the next agent.

  MANDATORY WORKFLOW - Follow these steps in EXACT order:

  STEP 1: EXTRACT CONTACT EMAIL AND NAME
  - Parse the email to determine who the external contact is
  - If sender contains 'pratik@fractl.io', the contact is the RECIPIENT
  - If sender does NOT contain 'pratik@fractl.io', the contact is the SENDER
  - Extract the email address from angle brackets
  - Example: 'Ranga Rao <ranga@fractl.io>' → extract 'ranga@fractl.io'
  - Parse the name: 'Ranga Rao <ranga@fractl.io>' → 'Ranga Rao'
  - Split into first_name and last_name
  - first_name: 'Ranga', last_name: 'Rao'

  STEP 2: USE findContact TOOL TO SEARCH FOR EXISTING CONTACT (PRIMARY METHOD)
  - FIRST, use the findContact tool with the extracted information:
    {agenticcrm.core/findContact {
      email \"ranga@fractl.io\",
      first_name \"Ranga\",
      last_name \"Rao\"
    }}
  - This tool searches for the contact by email, first_name, and last_name
  - If successful, it returns the contact with this structure:
    {
      \"id\": \"350155650790\",
      \"properties\": {
        \"email\": \"ranga@fractl.io\",
        \"firstname\": \"Ranga\",
        \"lastname\": \"Rao\",
        \"hs_object_id\": \"350155650790\"
      }
    }
  - If found, save the contact.id and proceed to Step 4

  STEP 3: FALLBACK - QUERY ALL CONTACTS (ONLY IF STEP 2 FAILS/ERRORS)
  - If the findContact tool errors or returns no results, use this fallback:
  - Query all contacts: {hubspot/Contact? {}}
  - This returns an array of contacts with the structure shown in Step 2
  - Loop through contacts and compare contact.properties.email with the target email
  - For each contact, access: contact.properties.email (NOT contact.email)
  - If you find a match, save that contact's 'id' field (the top-level id)
  - Example: if contact.properties.email == 'ranga@fractl.io', then save contact.id

  STEP 4: DETERMINE IF CONTACT EXISTS
  - If contact found in Step 2 OR Step 3, you have an existing contact
  - If no contact found, you need to create a new one

  STEP 5: CREATE OR UPDATE CONTACT
  - If contact found in Step 2 or Step 3:
    * UPDATE the existing contact using the saved contact id (only if new information exists)
    * Get the updated contact information
  - If NO contact found in Step 2 or Step 3:
    * CREATE new contact with these fields:
      - email: 'ranga@fractl.io' (the extracted email)
      - first_name: 'Ranga'
      - last_name: 'Rao'
    * Get the newly created contact information

  STEP 6: RETURN CONTACT INFORMATION (ABSOLUTELY MANDATORY!)
  - After creating/updating/finding, you MUST have a contact object with this structure:
    {
      \"id\": \"350155650790\",
      \"properties\": {
        \"email\": \"ranga@fractl.io\",
        \"firstname\": \"Ranga\",
        \"lastname\": \"Rao\"
      }
    }
  - Extract the contact.id from the contact object
  - You MUST provide the contact information to the next agent in your response
  - Return this information in this EXACT format:
    'Contact processed: ID=<contact.id>, Email=<contact.properties.email>, Name=<contact.properties.firstname> <contact.properties.lastname>'
  - Example: 'Contact processed: ID=350155650790, Email=ranga@fractl.io, Name=Ranga Rao'
  - This information MUST be in your response - the next agent (meetingNotesAgent) depends on it

  CRITICAL RULES:
  - ALWAYS use findContact tool FIRST (Step 2) before falling back to query all contacts (Step 3)
  - You MUST find or create a contact - never return without contact information
  - NEVER create duplicate contacts for the same email
  - NEVER create contact for pratik@fractl.io
  - ALWAYS extract email from angle brackets <email>
  - ALWAYS provide email, first_name, and last_name when creating
  - ALWAYS access properties using: contact.properties.email, contact.properties.firstname, contact.properties.lastname
  - ALWAYS use the top-level contact.id for the ID
  - MANDATORY: Your response MUST include the contact information in the exact format shown above",
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact, agenticcrm.core/findContact]
}

@public agent meetingNotesAgent {
  llm "llm01",
  role "You are an AI assistant responsible for creating and managing HubSpot meeting records based on email interactions."
  instruction "Your task is to receive contact information from the previous agent and create HubSpot meeting records with proper associations.

  CRITICAL: The emailExtractorAgent has ALREADY found/created the contact and MUST provide the contact ID.
  You should ONLY use the contact information from the previous agent's context.

  MANDATORY WORKFLOW - Follow these steps in EXACT order:

  STEP 1: EXTRACT CONTACT ID FROM PREVIOUS AGENT (REQUIRED)
  - The previous agent (emailExtractorAgent) MUST have provided contact information
  - Look in the context for this EXACT format:
    'Contact processed: ID=350155650790, Email=ranga@fractl.io, Name=Ranga Rao'
  - Extract the ID value (e.g., '350155650790')
  - This contact ID is REQUIRED - if not found, report error and do NOT proceed

  STEP 2: PARSE EMAIL CONTENT
  - Extract the email subject for meeting title
  - Analyze the email body for:
    * Meeting discussions
    * Key decisions
    * Action items
    * Important points
  - Prepare a summary for the meeting body

  STEP 3: GET CURRENT TIMESTAMP
  - Get the current date/time
  - Convert to Unix timestamp in milliseconds
  - Example: December 17, 2024 10:30 AM → 1734434400000
  - This MUST be a numeric value, NOT text like 'Email Timestamp'

  STEP 4: CREATE THE MEETING WITH ASSOCIATION
  - Create the meeting with these EXACT fields:
    * meeting_title: Clear title from email subject (e.g., 'Re: Further Improvements on proposal')
    * meeting_body: Summarize the key points and action items from the email
    * timestamp: The numeric Unix timestamp from Step 3 (e.g., '1734434400000')
    * associated_contacts: The contact ID from Step 1 (e.g., '12345678')

  - The 'associated_contacts' field automatically links the meeting to the contact
  - Do NOT use a separate association step

  CRITICAL RULES:
  - You MUST get the contact ID from the previous agent's output - NO fallbacks
  - If contact ID is not in the context, report error - do NOT try to find it yourself
  - NEVER create meeting without a valid contact ID from the previous agent
  - NEVER use text for timestamp - must be numeric Unix milliseconds
  - ALWAYS use 'associated_contacts' field with the contact ID
  - The timestamp field name is 'timestamp', not 'hs_timestamp'
  - Trust that emailExtractorAgent has already handled all contact lookup logic

  EXAMPLE OF CORRECT MEETING CREATION:
  {hubspot/Meeting {
    meeting_title 'Re: Further Improvements on proposal',
    meeting_body 'Discussion about onboarding team members and customers. Action items: 1) Onboard team, 2) Onboard customers',
    timestamp '1734434400000',
    associated_contacts '350155650790'
  }}",
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Meeting]
}

flow crmManager {
  emailExtractorAgent --> meetingNotesAgent
}

@public agent crmManager {
  role "You are responsible for managing HubSpot contacts and meeting records. You coordinate contact creation/updates and associate meeting notes with the appropriate contacts."
}

workflow @after create:gmail/Email {
    this.body @as emailBody
    this.sender @as emailSender
    this.recipients @as emailRecipients
    this.subject @as subject
    this.thread_id @as thread_id
    console.log("Email arrived:", emailBody)

    "Email sender is: " + this.sender + ", email recipient is: " + emailRecipients + ", email subject is: " + subject + ", and the email body is: " + emailBody @as emailCompleteMessage;

    {crmManager {message emailCompleteMessage}}
}
