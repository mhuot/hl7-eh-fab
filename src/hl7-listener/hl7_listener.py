#!/usr/bin/env python3
"""
HL7 MLLP Listener - Receives HL7 v2.x messages and forwards to Azure Event Hubs via Kafka protocol.
"""

import os
import socket
import threading
import json
import logging
from datetime import datetime
from confluent_kafka import Producer

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# MLLP framing characters
MLLP_START = b'\x0b'  # VT (vertical tab)
MLLP_END = b'\x1c\x0d'  # FS + CR

# Configuration from environment
MLLP_HOST = os.getenv('MLLP_HOST', '0.0.0.0')
MLLP_PORT = int(os.getenv('MLLP_PORT', '2575'))

# Event Hubs / Kafka configuration
EVENTHUB_NAMESPACE = os.getenv('EVENTHUB_NAMESPACE')
EVENTHUB_NAME = os.getenv('EVENTHUB_NAME', 'hl7-events')
EVENTHUB_CONNECTION_STRING = os.getenv('EVENTHUB_CONNECTION_STRING')


def create_kafka_producer():
    """Create Kafka producer configured for Azure Event Hubs."""
    if not EVENTHUB_NAMESPACE or not EVENTHUB_CONNECTION_STRING:
        logger.error("EVENTHUB_NAMESPACE and EVENTHUB_CONNECTION_STRING must be set")
        return None
    
    # Extract the shared access key from connection string
    # Format: Endpoint=sb://<namespace>.servicebus.windows.net/;SharedAccessKeyName=<name>;SharedAccessKey=<key>
    config = {
        'bootstrap.servers': f'{EVENTHUB_NAMESPACE}.servicebus.windows.net:9093',
        'security.protocol': 'SASL_SSL',
        'sasl.mechanism': 'PLAIN',
        'sasl.username': '$ConnectionString',
        'sasl.password': EVENTHUB_CONNECTION_STRING,
        'client.id': 'hl7-mllp-listener',
        'acks': 'all',
        'retries': 3,
    }
    
    return Producer(config)


def delivery_callback(err, msg):
    """Callback for Kafka message delivery."""
    if err:
        logger.error(f"Message delivery failed: {err}")
    else:
        logger.info(f"Message delivered to {msg.topic()} [{msg.partition()}] @ {msg.offset()}")


def parse_hl7_message(raw_message: bytes) -> dict:
    """Parse HL7 message and extract key fields."""
    try:
        # Decode and split into segments
        message_str = raw_message.decode('utf-8', errors='replace')
        segments = message_str.strip().split('\r')
        
        result = {
            'raw_message': message_str,
            'timestamp': datetime.utcnow().isoformat(),
            'segments': {}
        }
        
        for segment in segments:
            if not segment:
                continue
            fields = segment.split('|')
            segment_name = fields[0] if fields else 'UNKNOWN'
            
            # Extract key MSH fields
            if segment_name == 'MSH' and len(fields) > 9:
                result['message_type'] = fields[8] if len(fields) > 8 else None
                result['message_control_id'] = fields[9] if len(fields) > 9 else None
                result['sending_application'] = fields[2] if len(fields) > 2 else None
                result['sending_facility'] = fields[3] if len(fields) > 3 else None
                result['receiving_application'] = fields[4] if len(fields) > 4 else None
                result['receiving_facility'] = fields[5] if len(fields) > 5 else None
            
            # Extract patient info from PID
            if segment_name == 'PID' and len(fields) > 5:
                result['patient_id'] = fields[3] if len(fields) > 3 else None
                result['patient_name'] = fields[5] if len(fields) > 5 else None
            
            result['segments'][segment_name] = fields
        
        return result
    
    except Exception as e:
        logger.error(f"Error parsing HL7 message: {e}")
        return {
            'raw_message': raw_message.decode('utf-8', errors='replace'),
            'timestamp': datetime.utcnow().isoformat(),
            'parse_error': str(e)
        }


def create_ack(message_control_id: str, ack_code: str = 'AA') -> bytes:
    """Create HL7 ACK response."""
    timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
    ack = (
        f"MSH|^~\\&|HL7LISTENER|AZURE|SENDER|FACILITY|{timestamp}||ACK|{message_control_id}|P|2.5\r"
        f"MSA|{ack_code}|{message_control_id}|Message received successfully\r"
    )
    return MLLP_START + ack.encode('utf-8') + MLLP_END


def handle_client(client_socket: socket.socket, address: tuple, producer: Producer):
    """Handle incoming MLLP connection."""
    logger.info(f"Connection from {address}")
    buffer = b''
    
    try:
        while True:
            data = client_socket.recv(4096)
            if not data:
                break
            
            buffer += data
            
            # Check for complete MLLP message
            while MLLP_START in buffer and MLLP_END in buffer:
                start_idx = buffer.index(MLLP_START)
                end_idx = buffer.index(MLLP_END) + len(MLLP_END)
                
                # Extract message (without MLLP framing)
                mllp_message = buffer[start_idx + 1:end_idx - len(MLLP_END)]
                buffer = buffer[end_idx:]
                
                # Parse and forward to Event Hubs
                parsed = parse_hl7_message(mllp_message)
                logger.info(f"Received HL7 message: {parsed.get('message_type', 'UNKNOWN')}")
                
                if producer:
                    # Send to Event Hubs via Kafka
                    producer.produce(
                        EVENTHUB_NAME,
                        key=parsed.get('message_control_id', '').encode('utf-8'),
                        value=json.dumps(parsed).encode('utf-8'),
                        callback=delivery_callback
                    )
                    producer.poll(0)
                
                # Send ACK
                ack = create_ack(parsed.get('message_control_id', 'UNKNOWN'))
                client_socket.send(ack)
                logger.info(f"Sent ACK for message {parsed.get('message_control_id')}")
    
    except Exception as e:
        logger.error(f"Error handling client {address}: {e}")
    
    finally:
        client_socket.close()
        logger.info(f"Connection closed from {address}")


def main():
    """Main entry point."""
    logger.info(f"Starting HL7 MLLP Listener on {MLLP_HOST}:{MLLP_PORT}")
    
    # Create Kafka producer
    producer = create_kafka_producer()
    if producer:
        logger.info(f"Connected to Event Hubs namespace: {EVENTHUB_NAMESPACE}")
    else:
        logger.warning("Running without Event Hubs connection - messages will be logged only")
    
    # Create MLLP server socket
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind((MLLP_HOST, MLLP_PORT))
    server_socket.listen(5)
    
    logger.info(f"MLLP Listener ready on port {MLLP_PORT}")
    
    try:
        while True:
            client_socket, address = server_socket.accept()
            client_thread = threading.Thread(
                target=handle_client,
                args=(client_socket, address, producer)
            )
            client_thread.daemon = True
            client_thread.start()
    
    except KeyboardInterrupt:
        logger.info("Shutting down...")
    
    finally:
        if producer:
            producer.flush()
        server_socket.close()


if __name__ == '__main__':
    main()
