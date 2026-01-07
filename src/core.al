module agenticcrm.core

record ContactInfo {
    senderEmail String,
    senderFirstName String,
    senderLastname String,
    meetingTitle String,
    meetingBody String,
    meetingDate String,
    receiverEmail String,
    receiverFirstName String,
    receiverLastname String
}

record ContactSearchResult {
    contactFound Boolean,
    existingContactId String @optional
}

record ContactResult {
    finalContactId String
}

record OwnerResult {
    ownerEmail String,
    ownerId String @optional
}

record EmailFilterResult {
    shouldProcess Boolean
}

record SkipResult {
    skipped Boolean,
    reason String
}

event FindContactByEmail {
    email String
}

workflow FindContactByEmail {
    {hubspot/Contact {email? FindContactByEmail.email}} @as foundContacts;

    if (foundContacts.length > 0) {
        foundContacts @as [firstContact];
        {ContactSearchResult {
            contactFound true,
            existingContactId firstContact.id
        }}
    } else {
        {ContactSearchResult {
            contactFound false
        }}
    }
}

event FindOwnerByEmail {
    senderEmail String,
    receiverEmail String
}

workflow FindOwnerByEmail {
    {hubspot/Owner {email? FindOwnerByEmail.senderEmail}} @as senderAsFoundOwners;

    {hubspot/Owner {email? FindOwnerByEmail.receiverEmail}} @as receiverAsFoundOwners;

    if (senderAsFoundOwners.length > 0) {
        senderAsFoundOwners @as [firstOwner];
        {OwnerResult {
            ownerEmail FindOwnerByEmail.senderEmail,
            ownerId firstOwner.id
        }}
    } else {
        receiverAsFoundOwners @as [firstOwner];
        {OwnerResult {
            ownerEmail FindOwnerByEmail.receiverEmail,
            ownerId firstOwner.id
        }}
    }
}

@public agent filterEmail {
  llm "sonnet_llm",
  role "Extract email information from gmail/Email instance and analyze for CRM processing decisions."
  instruction "You receive a gmail/Email instance in {{message}}.

The {{message}} structure is a JSON object with an 'attributes' field containing:
- sender: string like 'Name <email@domain.com>'
- recipients: string like 'Name <email@domain.com>'
- subject: the email subject line
- body: the email body content
- date: ISO 8601 timestamp

YOUR TASK: Parse {{message}} and analyze these fields:
- sender: email sender address
- recipients: email recipient address
- subject: email subject line
- body: email content

Now understand the email subject and body along with sender and receipient and determine if this should be processed for CRM.

It should be processed if:
- Business discussion with clients/prospects
- Meeting coordination or follow-up
- Onboarding or sales conversation

It shouldn't be processed if:
- Automated sender (contains no-reply, noreply, automated)
- Newsletter (subject has unsubscribe, newsletter, digest)
- System notification or spam

Don't generate markdown format, just invoke the agenticcrm.core/EmailFilterResult and nothing else.",
  responseSchema agenticcrm.core/EmailFilterResult,
  retry classifyRetry
}

decision emailShouldBeProcessed {
  case (shouldProcess == true) {
    ProcessEmail
  }
  case (shouldProcess == false) {
    SkipEmail
  }
}

@public agent checkIfOwner {
  llm "sonnet_llm",
  role "Find the actual hubspot owner between sender and receipient of the email."
  instruction "Invoke FindOwnerByEmail tool with data from {{contactInfo}}.

You will receive senderEmail and receiverEmail from contactInfo.
You will need to invoke FindOwnerByEmail tool using these emails.",
  retry classifyRetry,
  tools [agenticcrm.core/FindOwnerByEmail]
}

@public agent parseEmailInfo {
  llm "sonnet_llm",
  role "Extract contact information, owner information, and meeting details from an email."
  instruction "You receive a gmail/Email instance in {{message}}.

The {{message}} structure is a JSON object with an 'attributes' field containing:
- sender: string like 'Name <email@domain.com>' or just 'email@domain.com'
- recipients: string like 'Name <email@domain.com>' or just 'email@domain.com'
- subject: the email subject line
- body: the email body content
- date: ISO 8601 timestamp

STEP 1: Extract emails and names from {{message}}.attributes
- From sender: extract email address and name (if 'Name <email>' format, extract both; if just 'email', you can extract firstName from email body saying 'Hi, ' or similar salutations and name)
- From recipients: same extraction logic

STEP 2: Determine both emails to figure out which is owner and contact for next agent:
- From sender, you need to only put the email of sender on senderEmail.
- From receiver, you need to only put the email of receiver on receiverEmail.

STEP 3: Extract meeting details from {{message}}.attributes
- meetingTitle: exact value from subject field
- meetingDate: exact value from date field (keep ISO 8601 format)
- meetingBody: summarize the body of email on descriptive clear structure, if there are things mentioned as action, creation action items with numbering.

STEP 4: Return ContactInfo with ACTUAL extracted values:
- senderEmail, senderFirstname, senderLastname
- receiverEmail, receiverFirstName, receiverLastname
- meetingTitle, meetingBody, meetingDate

DO NOT return empty strings - extract actual values from {{message}}.attributes.",
  responseSchema agenticcrm.core/ContactInfo,
  retry classifyRetry
}

@public agent findExistingContact {
  llm "sonnet_llm",
  role "Search for an existing contact in HubSpot by email address."
  instruction "Call agenticcrm.core/FindContactByEmail with the exact email from {{contactEmail}}.

Return the result:
- contactFound: true or false
- existingContactId: the contact ID if found",
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

workflow updateExistingContact {
  {ContactResult {
    finalContactId existingContactId
  }}
}

@public agent createNewContact {
  llm "sonnet_llm",
  role "Create a new contact in HubSpot CRM."
  instruction "Create contact using hubspot/Contact with:
- email from {{contactEmail}}
- first_name from {{firstName}}
- last_name from {{lastName}}

Return finalContactId with the id from the created contact.",
  responseSchema agenticcrm.core/ContactResult,
  retry classifyRetry,
  tools [hubspot/Contact]
}


decision contactIsOwner {
  case (isOwner == true) {
    SkipContactCreation
  }
  case (isOwner == false) {
    ProceedWithContact
  }
}

workflow findOwner {
  {agenticcrm.core/FindOwnerByEmail {email ownerEmail}}
}

workflow skipProcessing {
  {SkipResult {
    skipped true,
    reason "Email filtered out (automated sender or newsletter)"
  }}
}

workflow skipOwnerContact {
  {ContactResult {
    finalContactId null
  }}
}

@public agent createMeeting {
  llm "sonnet_llm",
  role "Create a meeting record in HubSpot to log the email interaction."
  instruction "Convert {{meetingDate}} from ISO 8601 to Unix milliseconds.
Calculate end time as start + 3600000 (1 hour).

Create meeting using hubspot/Meeting with:
- meeting_title from {{meetingTitle}}
- meeting_body from {{meetingBody}}
- timestamp: Unix milliseconds as string
- meeting_outcome: 'COMPLETED'
- meeting_start_time: Unix milliseconds as string
- meeting_end_time: start + 3600000 as string
- owner from {{ownerId}} (null if not available)
- associated_contacts from {{finalContactId}} (omit if null)

All timestamps must be Unix milliseconds as strings.",
  retry classifyRetry,
  tools [hubspot/Meeting]
}

flow crmManager {
  filterEmail --> emailShouldBeProcessed
  emailShouldBeProcessed --> "SkipEmail" skipProcessing
  emailShouldBeProcessed --> "ProcessEmail" parseEmailInfo
  parseEmailInfo --> checkIfOwner
  checkIfOwner --> contactIsOwner
  contactIsOwner --> "SkipContactCreation" skipOwnerContact
  contactIsOwner --> "ProceedWithContact" findExistingContact
  findExistingContact --> contactExistsCheck
  contactExistsCheck --> "ContactExists" updateExistingContact
  contactExistsCheck --> "ContactNotFound" createNewContact
  skipOwnerContact --> findOwner
  updateExistingContact --> findOwner
  createNewContact --> findOwner
  findOwner --> createMeeting
}

@public agent crmManager {
  role "You coordinate the complete CRM workflow: extract contact and meeting information from the email, find or create the contact in HubSpot, find the owner, and create the meeting with proper associations."
}

workflow @after create:gmail/Email {
    {crmManager {message gmail/Email}}
}
