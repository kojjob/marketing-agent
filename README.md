# Marketing Automation Agent

An Elixir/Phoenix-powered marketing automation agent that handles contact enrichment, email campaigns, and automated follow-ups while keeping humans in control of strategy and compliance.

## Features

- **Contact Management**: Import, track, and segment marketing contacts
- **Contact Enrichment**: Find emails and company data using Apollo.io
- **Email Campaigns**: Send personalized emails via SendGrid
- **Template System**: Markdown-based templates with variable substitution
- **Automated Follow-ups**: Scheduled follow-up sequences
- **Engagement Tracking**: Track opens, clicks, and replies
- **Human Approval Layer**: All sends require explicit confirmation
- **Compliance Built-in**: CAN-SPAM and GDPR compliant by design

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                 Marketing Agent (Elixir)                 │
│  • Contact management & segmentation                     │
│  • Template rendering & personalization                  │
│  • Workflow orchestration                                │
│  • Performance analytics                                 │
├─────────────────────────────────────────────────────────┤
│                    Integrations                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │ SendGrid │  │ Apollo   │  │ SQLite   │              │
│  │ (Email)  │  │ (Enrich) │  │ (Data)   │              │
│  └──────────┘  └──────────┘  └──────────┘              │
├─────────────────────────────────────────────────────────┤
│                 Human Approval Layer                     │
│  • Approve templates before send                         │
│  • Review enriched contacts                              │
│  • Confirm all campaign sends                            │
│  • Handle replies manually                               │
└─────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Prerequisites

- Elixir 1.15+
- Erlang 26+

### 2. Clone and Setup

```bash
cd marketing_agent
mix deps.get
```

### 3. Configure API Keys

```bash
cp .env.example .env
# Edit .env with your API keys
```

**Required API keys:**
- [SendGrid](https://sendgrid.com) - For sending emails (free tier: 100/day)
- [Apollo.io](https://apollo.io) - For contact enrichment (free tier: 50 credits/month)

### 4. Initialize Database

```bash
mix ecto.setup
```

### 5. Build CLI (Optional)

```bash
mix escript.build
./marketing help
```

Or run directly with Mix:

```bash
mix run -e "MarketingAgent.CLI.main([\"help\"])"
```

## Usage

### Import Contacts

```bash
# From CSV file
./marketing add-contacts prospects.csv

# Single contact
./marketing add-contact --company "Acme Corp" --email "john@acme.com" --name "John Doe"
```

**CSV Format:**
```csv
company,first_name,last_name,email,title,segment,personalization
Acme Corp,John,Doe,john@acme.com,VP Engineering,enterprise,your innovative platform
```

### Enrich Contacts

Find missing emails and company data:

```bash
# Enrich contacts without emails
./marketing enrich --limit 20

# Enrich specific segment
./marketing enrich --segment "white-label-dsp"

# Check remaining credits
./marketing credits
```

### Create & Send Campaigns

```bash
# List available templates
./marketing templates

# Preview a template
./marketing preview-template cold-email-1

# Create campaign
./marketing create-campaign --template cold-email-1 --segment "enriched"

# Preview campaign (see recipients and sample email)
./marketing preview --campaign <campaign-id>

# Send campaign (requires confirmation)
./marketing send --campaign <campaign-id> --confirm
```

### Automated Follow-ups

Follow-ups are automatically scheduled after initial sends:
- Day 3: First follow-up (if no open)
- Day 7: Second follow-up (if opened but no reply)
- Day 14: Breakup email

```bash
# Check pending follow-ups
./marketing send-followups

# Send follow-ups (requires confirmation)
./marketing send-followups --confirm
```

### Analytics

```bash
# Overall statistics
./marketing stats

# Campaign-specific report
./marketing report --campaign <campaign-id>
```

## Email Templates

Templates are stored in `priv/templates/` as Markdown files with YAML frontmatter.

### Template Format

```markdown
---
subject: Quick question about {{company}}'s RTB stack
description: Initial cold outreach for DSP/SSP prospects
variables: first_name, company, personalization
---

Hi {{first_name}},

I noticed {{company}} {{personalization}}.

[Rest of your email...]

Best,
[Your Name]
```

### Available Variables

| Variable | Description |
|----------|-------------|
| `{{first_name}}` | Contact's first name |
| `{{last_name}}` | Contact's last name |
| `{{full_name}}` | Full name |
| `{{company}}` | Company name |
| `{{title}}` | Job title |
| `{{personalization}}` | Custom personalization hook |
| `{{industry}}` | Company industry |
| `{{company_size}}` | Company size |

### Included Templates

- `cold-email-1.md` - Initial outreach
- `follow-up-1.md` - First follow-up (Day 3)
- `follow-up-2.md` - Second follow-up (Day 7)
- `breakup.md` - Final follow-up (Day 14)

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `SENDGRID_API_KEY` | SendGrid API key | Yes |
| `APOLLO_API_KEY` | Apollo.io API key | Yes |
| `FROM_EMAIL` | Sender email address | Yes |
| `FROM_NAME` | Sender name | Yes |
| `REPLY_TO` | Reply-to email | No |
| `UNSUBSCRIBE_URL` | Unsubscribe page URL | Yes |
| `COMPANY_ADDRESS` | Physical address (CAN-SPAM) | Yes |

### Application Config

Edit `config/config.exs` to customize:

```elixir
config :marketing_agent, MarketingAgent.Config,
  # Follow-up schedule (days after initial email)
  followup_schedule: [3, 7, 14],
  # Daily sending limit
  daily_send_limit: 100,
  # Timezone for scheduling
  timezone: "America/New_York"
```

## Compliance

### CAN-SPAM Requirements (Automatically Handled)

- ✅ Includes unsubscribe link in every email
- ✅ Includes physical address in footer
- ✅ Tracks unsubscribes
- ✅ Honors opt-outs

### GDPR Considerations

- ✅ Tracks consent source for each contact
- ✅ Supports data deletion requests
- ✅ Stores minimal necessary data

### Best Practices

- Never purchase email lists for EU contacts
- Document how you obtained each contact
- Honor unsubscribe requests immediately
- Don't send more than needed

## Web Interface (Optional)

Start the Phoenix server for a web dashboard:

```bash
mix phx.server
```

Visit `http://localhost:4000` for:
- Campaign management
- Contact search
- Analytics dashboard
- Webhook endpoints for SendGrid events

## Webhook Setup (Optional)

To track email opens, clicks, and bounces in real-time, configure SendGrid webhooks:

1. Go to SendGrid Settings → Mail Settings → Event Webhooks
2. Add your webhook URL: `https://yourdomain.com/webhooks/sendgrid`
3. Select events: Delivered, Opened, Clicked, Bounced, Unsubscribed

## API Costs

| Service | Free Tier | Paid Tier |
|---------|-----------|-----------|
| SendGrid | 100 emails/day | From $19.95/mo |
| Apollo.io | 50 credits/month | From $49/mo |

**Estimated monthly cost for moderate volume:** $50-100

## Limitations

- **No LinkedIn automation**: LinkedIn TOS prohibits automation
- **Human approval required**: All sends need explicit confirmation
- **You handle replies**: Agent doesn't respond to emails
- **Free tier limits**: May need paid plans for volume

## Development

```bash
# Run tests
mix test

# Start IEx with application
iex -S mix

# Format code
mix format
```

## Troubleshooting

### "SendGrid API key not configured"

Make sure your `.env` file exists and contains `SENDGRID_API_KEY`.

### "Apollo API key not configured"

Make sure your `.env` file contains `APOLLO_API_KEY`.

### Emails not being sent

1. Check SendGrid dashboard for errors
2. Verify domain is verified in SendGrid
3. Check daily send limit hasn't been reached

### Enrichment not finding contacts

1. Verify Apollo API key is valid
2. Check remaining credits with `./marketing credits`
3. Try enriching with more data (name, domain)

## License

MIT License - Use freely for your marketing automation needs.
