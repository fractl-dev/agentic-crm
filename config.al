{
  "agentlang": {
    "service": {
      "port": 8080
    },
    "store": {
      "type": "sqlite",
      "dbname": "agenticcrm.db"
    },
    "monitoring": {
      "enabled": false
    },
    "retry": [
      {
        "name": "classifyRetry",
        "attempts": 3,
        "backoff": {
          "strategy": "linear",
          "delay": 2,
          "magnitude": "seconds",
          "factor": 2
        }
      }
    ],
    "rbac": {
      "enabled": false
    },
    "auth": {
      "enabled": false
    },
    "auditTrail": {
      "enabled": true
    }
  },
  "agentlang.ai": [
    {
      "agentlang.ai/LLM": {
        "name": "sonnet_llm",
        "service": "anthropic",
        "config": {
          "model": "claude-sonnet-4-5",
          "maxTokens": 21333,
          "enableThinking": false,
          "temperature": 0.7,
          "budgetTokens": 8192,
          "enablePromptCaching": true,
          "stream": false,
          "enableExtendedOutput": true
        }
      }
    },
    {
      "agentlang.ai/LLM": {
        "name": "old_sonnet_llm",
        "service": "anthropic",
        "config": {
          "model": "claude-haiku-4-5",
          "maxTokens": 21333,
          "enableThinking": false,
          "temperature": 0.7,
          "budgetTokens": 8192,
          "enablePromptCaching": true,
          "stream": false,
          "enableExtendedOutput": true
        }
      }
    },
    {
      "agentlang.ai/LLM": {
        "name": "crmManager_llm",
        "service": "openai",
        "config": {}
      }
    }
  ]
}