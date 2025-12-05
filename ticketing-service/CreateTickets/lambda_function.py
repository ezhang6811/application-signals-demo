import json
import boto3
import os
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    try:
        body = json.loads(event['body']) if isinstance(event.get('body'), str) else event.get('body', {})
        
        ticket_id = str(uuid.uuid4())
        
        item = {
            'ticket_id': ticket_id,
            'title': body.get('title', ''),
            'description': body.get('description', ''),
            'status': 'open',
            'created_at': datetime.utcnow().isoformat()
        }
        
        table.put_item(Item=item)
        
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'ticket_id': ticket_id,
                'message': 'Ticket created successfully'
            })
        }
    except Exception as e:
        print(f"Error creating ticket: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Failed to create ticket',
                'message': str(e)
            })
        }
