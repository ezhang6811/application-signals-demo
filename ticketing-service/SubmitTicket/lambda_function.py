import json
import boto3
import os

sqs = boto3.client('sqs')
QUEUE_URL = os.environ['QUEUE_URL']
MAX_MESSAGE_SIZE = 256 * 1024

def lambda_handler(event, context):
    try:
        body = json.loads(event['body']) if isinstance(event.get('body'), str) else event.get('body', {})
        
        ticket = {
            'ticket_id': body.get('ticket_id', ''),
            'title': body.get('title', ''),
            'description': body.get('description', ''),
            'priority': body.get('priority', 'medium')
        }
        
        message_body = json.dumps(ticket)
        message_size = len(message_body.encode('utf-8'))
        
        if message_size > MAX_MESSAGE_SIZE:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Message size exceeds limit',
                    'message': f'Message size ({message_size} bytes) exceeds SQS limit ({MAX_MESSAGE_SIZE} bytes)',
                    'suggestion': 'Reduce description length or use S3 for large payloads'
                })
            }
        
        response = sqs.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=message_body
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Ticket submitted successfully',
                'message_id': response['MessageId']
            })
        }
    except Exception as e:
        print(f"Error submitting ticket: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Failed to submit ticket',
                'message': str(e)
            })
        }
