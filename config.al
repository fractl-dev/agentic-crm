{
    "agentlang": {
        "service": {
            "port": "#js parseInt(getLocalEnv('PORT', '8080'))"
        },
        "store": {
            "type": "sqlite",
            "dbname": "agenticcrm.db"
        },
        "monitoring": {
            "enabled": true
        }
    },
    "agentlang.ai": [
        {
            "agentlang.ai/LLM": {
                "name": "llm01",
                "service": "openai",
                "config": {
                    "model": "gpt-5.2"
                }
            }
        }
    ]
}
