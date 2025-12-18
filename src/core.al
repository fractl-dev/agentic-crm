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

@public agent parseEmailInfo {
  llm "llm01",
  role "You extract email addresses and names from email messages."
  instruction "Your ONLY task is to parse the email message and extract contact information.

  STEP 1: IDENTIFY WHO IS THE EXTERNAL CONTACT
  - If the sender contains 'pratik@fractl.io', the external contact is the RECIPIENT
  - If the sender does NOT contain 'pratik@fractl.io', the external contact is the SENDER
  - Never extract pratik@fractl.io as the contact

  STEP 2: EXTRACT EMAIL ADDRESS
  - Extract ONLY the email address from angle brackets
  - Example: 'Ranga Rao <ranga@fractl.io>' → extract 'ranga@fractl.io'

  STEP 3: EXTRACT NAME
  - Parse the name from the email header
  - Example: 'Ranga Rao <ranga@fractl.io>' → 'Ranga Rao'
  - Split into first_name and last_name
  - Example: first_name='Ranga', last_name='Rao'

  STEP 4: RETURN THE EXTRACTED INFORMATION
  - Return in this EXACT format:
    'Extracted: Email=ranga@fractl.io, FirstName=Ranga, LastName=Rao'
  - This format is MANDATORY

  CRITICAL RULES:
  - Extract ONLY - do NOT query or create anything
  - NEVER extract pratik@fractl.io as a contact
  - ALWAYS return the information in the exact format specified",
  retry agenticcrm.core/classifyRetry
}

@public agent findExistingContact {
  llm "llm01",
  role "You search for existing HubSpot contacts."
  instruction "Your ONLY task is to search for an existing contact in HubSpot.

  STEP 1: EXTRACT EMAIL FROM PREVIOUS AGENT
  - Look for the format: 'Extracted: Email=ranga@fractl.io, FirstName=Ranga, LastName=Rao'
  - Extract the email address (e.g., 'ranga@fractl.io')

  STEP 2: QUERY ALL HUBSPOT CONTACTS
  - Use: {hubspot/Contact? {}}
  - This returns all contacts with structure:
    {
      \"id\": \"350155650790\",
      \"properties\": {
        \"email\": \"ranga@fractl.io\",
        \"firstname\": \"Ranga\",
        \"lastname\": \"Rao\"
      }
    }

  STEP 3: LOOP THROUGH CONTACTS TO FIND MATCH
  - For each contact in the results, access: contact.properties.email
  - Compare contact.properties.email with the target email from Step 1
  - If match found, extract contact.id (the top-level id)

  STEP 4: RETURN THE RESULT
  - If contact found, return: 'Found: ID=350155650790, Email=ranga@fractl.io'
  - If contact NOT found, return: 'NotFound: Email=ranga@fractl.io, FirstName=Ranga, LastName=Rao'
  - Use the EXACT format specified

  CRITICAL RULES:
  - Search ONLY - do NOT create or update anything
  - MUST query ALL contacts and loop through them
  - Access email at contact.properties.email (NOT contact.email)
  - Return in the EXACT format specified",
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact]
}

@public agent createOrUpdateContact {
  llm "llm01",
  role "You create or update HubSpot contacts."
  instruction "Your ONLY task is to create a new contact or update an existing one.

  STEP 1: CHECK WHAT THE PREVIOUS AGENT FOUND
  - Look for either:
    * 'Found: ID=350155650790, Email=ranga@fractl.io' (contact exists)
    * 'NotFound: Email=ranga@fractl.io, FirstName=Ranga, LastName=Rao' (contact doesn't exist)

  STEP 2A: IF CONTACT EXISTS (Found)
  - Extract the contact ID
  - You can optionally UPDATE the contact if new information is available
  - Get the contact information

  STEP 2B: IF CONTACT DOESN'T EXIST (NotFound)
  - Extract: Email, FirstName, LastName from the NotFound message
  - CREATE a new contact with:
    * email: the extracted email
    * first_name: the extracted FirstName
    * last_name: the extracted LastName
  - Get the newly created contact information

  STEP 3: RETURN CONTACT INFORMATION
  - Return in this EXACT format:
    'Contact: ID=350155650790, Email=ranga@fractl.io, Name=Ranga Rao'
  - This format is MANDATORY - the next agents depend on it

  CRITICAL RULES:
  - Create or update ONLY - do NOT search
  - ALWAYS return contact information in the exact format
  - Access properties at contact.properties.email, contact.properties.firstname, contact.properties.lastname
  - Use top-level contact.id for the ID",
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact]
}

@public agent parseEmailContent {
  llm "llm01",
  role "You parse email content to extract meeting information."
  instruction "Your ONLY task is to analyze the email and prepare meeting information.

  STEP 1: EXTRACT EMAIL SUBJECT
  - Look for the email subject in the context
  - This will be the meeting title

  STEP 2: ANALYZE EMAIL BODY
  - Read the email body
  - Identify:
    * Meeting discussions
    * Key decisions
    * Action items
    * Important points

  STEP 3: PREPARE MEETING SUMMARY
  - Create a concise summary of the email
  - Focus on key points and action items
  - This will be the meeting body

  STEP 4: RETURN MEETING INFORMATION
  - Return in this EXACT format:
    'Meeting: Title=[email subject], Body=[summary of key points and action items]'
  - This format is MANDATORY

  CRITICAL RULES:
  - Parse ONLY - do NOT create anything
  - Return meeting information in the exact format specified",
  retry agenticcrm.core/classifyRetry
}

@public agent createMeeting {
  llm "llm01",
  role "You create HubSpot meetings and associate them with contacts."
  instruction "Your ONLY task is to create a meeting and link it to the contact.

  STEP 1: EXTRACT CONTACT ID FROM CONTEXT
  - Look for: 'Contact: ID=350155650790, Email=ranga@fractl.io, Name=Ranga Rao'
  - Extract the contact ID (e.g., '350155650790')
  - This is REQUIRED

  STEP 2: EXTRACT MEETING INFORMATION FROM CONTEXT
  - Look for: 'Meeting: Title=[...], Body=[...]'
  - Extract the Title and Body

  STEP 3: GENERATE TIMESTAMP
  - Get the current date/time
  - Convert to Unix timestamp in milliseconds
  - Example: 1734434400000
  - MUST be a numeric value, NOT text

  STEP 4: CREATE THE MEETING
  - Create meeting with these fields:
    * meeting_title: the extracted Title
    * meeting_body: the extracted Body
    * timestamp: the numeric Unix timestamp
    * associated_contacts: the contact ID from Step 1
  - Example:
    {hubspot/Meeting {
      meeting_title 'Re: Further Improvements on proposal',
      meeting_body 'Discussion about onboarding team members...',
      timestamp '1734434400000',
      associated_contacts '350155650790'
    }}

  CRITICAL RULES:
  - Create ONLY - do NOT search for contacts
  - MUST have contact ID from previous agent
  - Use numeric timestamp in milliseconds
  - Use 'timestamp' field name (NOT 'hs_timestamp')
  - Use 'associated_contacts' field with contact ID",
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Meeting]
}

// FLOWS: Connect agents in sequence
flow contactFlow {
  parseEmailInfo --> findExistingContact
  findExistingContact --> createOrUpdateContact
}

flow meetingFlow {
  parseEmailContent --> createMeeting
}

flow crmManager {
  contactFlow --> meetingFlow
}

// Orchestrator agent
@public agent crmManager {
  role "You coordinate the contact and meeting creation workflow."
}

// Workflow: Trigger on email arrival
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
