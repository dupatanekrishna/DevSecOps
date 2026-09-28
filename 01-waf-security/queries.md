# CloudWatch Logs Insights Queries

Select the WAF log group:

~~~text
aws-waf-logs-devsecops-waf-lab
~~~

## Recent Requests

~~~sql
fields @timestamp,
       action,
       terminatingRuleId,
       httpRequest.clientIp,
       httpRequest.country,
       httpRequest.httpMethod,
       httpRequest.uri,
       httpRequest.args
| sort @timestamp desc
| limit 50
~~~

## Blocked Requests by Rule

~~~sql
fields action, terminatingRuleId
| filter action = "BLOCK"
| stats count(*) as blockedRequests by terminatingRuleId
| sort blockedRequests desc
~~~

## Blocked Requests by IP and Rule

~~~sql
fields httpRequest.clientIp, terminatingRuleId
| filter action = "BLOCK"
| stats count(*) as blockedRequests by httpRequest.clientIp, terminatingRuleId
| sort blockedRequests desc
~~~

## Managed XSS Detection

~~~sql
fields @timestamp,
       action,
       terminatingRuleId,
       ruleGroupList,
       labels,
       httpRequest.uri,
       httpRequest.args
| filter httpRequest.args like /script/
| sort @timestamp desc
| limit 20
~~~

## COUNT Mode Details

~~~sql
fields @timestamp,
       action,
       terminatingRuleId,
       httpRequest.uri,
       httpRequest.args,
       nonTerminatingMatchingRules.0.ruleId as detectedRuleGroup,
       nonTerminatingMatchingRules.0.action as detectedAction,
       nonTerminatingMatchingRules.0.ruleMatchDetails.0.conditionType as condition,
       nonTerminatingMatchingRules.0.ruleMatchDetails.0.matchedFieldName as matchedField,
       labels.0.name as wafLabel
| sort @timestamp desc
| limit 50
~~~

## Rate-Limit Blocks

~~~sql
fields @timestamp,
       action,
       terminatingRuleId,
       httpRequest.clientIp,
       httpRequest.args
| filter terminatingRuleId = "RateLimitPerIP"
| sort @timestamp desc
| limit 100
~~~

## Tuned XSS Comparison

~~~sql
fields @timestamp,
       action,
       terminatingRuleId,
       httpRequest.uri,
       httpRequest.args,
       labels.0.name as wafLabel
| filter httpRequest.args like /script/
   or httpRequest.uri = "/admin"
| sort @timestamp desc
| limit 20
~~~

Expected behavior:

~~~text
/docs.html + XSS-like query → ALLOW / Default_Action / XSS label
/ + XSS-like query          → BLOCK / BlockXSSExceptDocs / XSS label
/admin                      → BLOCK / BlockAdminPath
~~~
