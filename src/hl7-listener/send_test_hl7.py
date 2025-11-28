#!/usr/bin/env python3
"""
HL7 ADT Message Sender
Sends unique ADT messages via MLLP to a specified endpoint
"""

import socket
import random
import string
from datetime import datetime, timedelta
import time
import argparse

# MLLP framing characters
MLLP_START = b'\x0b'
MLLP_END = b'\x1c\x0d'

# Sample data for generating realistic messages
FIRST_NAMES = [
    "James", "Mary", "John", "Patricia", "Robert", "Jennifer", "Michael", "Linda",
    "William", "Elizabeth", "David", "Barbara", "Richard", "Susan", "Joseph", "Jessica",
    "Thomas", "Sarah", "Charles", "Karen", "Christopher", "Nancy", "Daniel", "Lisa",
    "Matthew", "Betty", "Anthony", "Margaret", "Mark", "Sandra", "Donald", "Ashley",
    "Steven", "Kimberly", "Paul", "Emily", "Andrew", "Donna", "Joshua", "Michelle",
    "Kenneth", "Dorothy", "Kevin", "Carol", "Brian", "Amanda", "George", "Melissa",
    "Timothy", "Deborah"
]

LAST_NAMES = [
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
    "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson",
    "Thomas", "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson",
    "White", "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson", "Walker",
    "Young", "Allen", "King", "Wright", "Scott", "Torres", "Nguyen", "Hill", "Flores",
    "Green", "Adams", "Nelson", "Baker", "Hall", "Rivera", "Campbell", "Mitchell", "Carter"
]

STREETS = [
    "Main St", "Oak Ave", "Maple Dr", "Cedar Ln", "Pine Rd", "Elm St", "Washington Blvd",
    "Park Ave", "Lake Dr", "River Rd", "Hill St", "Forest Ave", "Sunset Blvd", "Spring St",
    "Valley Rd", "Mountain View Dr", "Church St", "School Rd", "Mill St", "Bridge Ave"
]

CITIES = [
    ("Minneapolis", "MN", "554"),
    ("St Paul", "MN", "551"),
    ("Chicago", "IL", "606"),
    ("Milwaukee", "WI", "532"),
    ("Denver", "CO", "802"),
    ("Seattle", "WA", "981"),
    ("Portland", "OR", "972"),
    ("Phoenix", "AZ", "850"),
    ("Dallas", "TX", "752"),
    ("Houston", "TX", "770")
]

ADT_EVENTS = [
    ("A01", "ADT^A01", "Admit/Visit Notification"),
    ("A02", "ADT^A02", "Transfer a Patient"),
    ("A03", "ADT^A03", "Discharge/End Visit"),
    ("A04", "ADT^A04", "Register a Patient"),
    ("A08", "ADT^A08", "Update Patient Information"),
    ("A11", "ADT^A11", "Cancel Admit"),
    ("A12", "ADT^A12", "Cancel Transfer"),
    ("A13", "ADT^A13", "Cancel Discharge")
]

PATIENT_CLASSES = ["I", "O", "E", "P", "R"]  # Inpatient, Outpatient, Emergency, Preadmit, Recurring
ADMIT_SOURCES = ["1", "2", "3", "4", "5", "6", "7", "8"]
HOSPITALS = ["MAIN", "NORTH", "SOUTH", "EAST", "WEST"]
UNITS = ["ICU", "MED", "SURG", "PEDS", "OB", "ER", "ORTH", "CARD", "NEURO", "ONCO"]


def generate_control_id():
    """Generate a unique message control ID"""
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S%f")
    random_suffix = ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))
    return f"{timestamp}{random_suffix}"


def generate_mrn():
    """Generate a medical record number"""
    return f"MRN{random.randint(100000, 999999)}"


def generate_account_number():
    """Generate a patient account number"""
    return f"ACC{random.randint(1000000, 9999999)}"


def generate_ssn():
    """Generate a fake SSN for testing"""
    return f"{random.randint(100, 999)}-{random.randint(10, 99)}-{random.randint(1000, 9999)}"


def generate_phone():
    """Generate a phone number"""
    return f"({random.randint(200, 999)}){random.randint(200, 999)}-{random.randint(1000, 9999)}"


def generate_dob():
    """Generate a date of birth between 1940 and 2020"""
    start_date = datetime(1940, 1, 1)
    end_date = datetime(2020, 12, 31)
    delta = end_date - start_date
    random_days = random.randint(0, delta.days)
    dob = start_date + timedelta(days=random_days)
    return dob.strftime("%Y%m%d")


def generate_admit_datetime():
    """Generate an admit datetime within the last 30 days"""
    now = datetime.now()
    random_days = random.randint(0, 30)
    random_hours = random.randint(0, 23)
    random_minutes = random.randint(0, 59)
    admit_time = now - timedelta(days=random_days, hours=random_hours, minutes=random_minutes)
    return admit_time.strftime("%Y%m%d%H%M%S")


def generate_hl7_message(sequence_num):
    """Generate a complete HL7 ADT message"""
    
    # Pick random data
    first_name = random.choice(FIRST_NAMES)
    last_name = random.choice(LAST_NAMES)
    gender = random.choice(["M", "F"])
    dob = generate_dob()
    mrn = generate_mrn()
    account = generate_account_number()
    ssn = generate_ssn()
    phone = generate_phone()
    
    street_num = random.randint(100, 9999)
    street = random.choice(STREETS)
    city, state, zip_prefix = random.choice(CITIES)
    zip_code = f"{zip_prefix}{random.randint(10, 99)}"
    
    event_code, event_type, event_desc = random.choice(ADT_EVENTS)
    patient_class = random.choice(PATIENT_CLASSES)
    hospital = random.choice(HOSPITALS)
    unit = random.choice(UNITS)
    room = f"{random.randint(1, 9)}{random.randint(0, 9)}{random.randint(0, 9)}"
    bed = random.choice(["A", "B", "C", "D"])
    
    control_id = generate_control_id()
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    admit_datetime = generate_admit_datetime()
    
    attending_id = f"DR{random.randint(1000, 9999)}"
    attending_last = random.choice(LAST_NAMES)
    attending_first = random.choice(FIRST_NAMES)
    
    # Build the message segments
    segments = []
    
    # MSH - Message Header
    msh = (
        f"MSH|^~\\&|SENDING_APP|SENDING_FAC|RECEIVING_APP|RECEIVING_FAC|{timestamp}||"
        f"{event_type}|{control_id}|P|2.5.1|||AL|NE"
    )
    segments.append(msh)
    
    # EVN - Event Type
    evn = f"EVN|{event_code}|{timestamp}|||ADMIN^SYSTEM"
    segments.append(evn)
    
    # PID - Patient Identification
    pid = (
        f"PID|1||{mrn}^^^{hospital}^MR~{ssn}^^^SSN^SS||{last_name}^{first_name}^^^||"
        f"{dob}|{gender}|||{street_num} {street}^^{city}^{state}^{zip_code}^USA||"
        f"{phone}|||S|||{account}|||||||||||N"
    )
    segments.append(pid)
    
    # PV1 - Patient Visit
    pv1 = (
        f"PV1|1|{patient_class}|{hospital}^{unit}^{room}^{bed}||||"
        f"{attending_id}^{attending_last}^{attending_first}^^^DR|||{unit}||||"
        f"{random.choice(ADMIT_SOURCES)}|||{attending_id}^{attending_last}^{attending_first}^^^DR|"
        f"||||||||||||||||||||||||||{admit_datetime}"
    )
    segments.append(pv1)
    
    # PV2 - Patient Visit Additional Info (for some messages)
    if random.random() > 0.5:
        pv2 = f"PV2|||^Testing HL7 ADT Message {sequence_num}"
        segments.append(pv2)
    
    # Join segments with carriage return
    message = "\r".join(segments) + "\r"
    
    return message, control_id, event_type, f"{last_name}, {first_name}"


def wrap_mllp(message):
    """Wrap message in MLLP framing"""
    return MLLP_START + message.encode('utf-8') + MLLP_END


def send_message(sock, message):
    """Send a single MLLP-wrapped message and wait for ACK"""
    wrapped = wrap_mllp(message)
    sock.sendall(wrapped)
    
    # Receive ACK (with timeout)
    response = b''
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        response += chunk
        if MLLP_END in response:
            break
    
    return response.decode('utf-8', errors='replace')


def parse_ack(response):
    """Parse ACK response to determine success/failure"""
    if not response:
        return False, "No response received"
    
    # Strip MLLP framing
    response = response.replace('\x0b', '').replace('\x1c', '').replace('\r\n', '\r')
    
    # Look for MSA segment
    for segment in response.split('\r'):
        if segment.startswith('MSA|'):
            fields = segment.split('|')
            if len(fields) >= 2:
                ack_code = fields[1]
                if ack_code in ['AA', 'CA']:
                    return True, ack_code
                else:
                    error_msg = fields[3] if len(fields) > 3 else "Unknown error"
                    return False, f"{ack_code}: {error_msg}"
    
    return False, "No MSA segment in response"


def main():
    parser = argparse.ArgumentParser(description='Send HL7 ADT messages via MLLP')
    parser.add_argument('--host', default='localhost', help='Target host (default: localhost)')
    parser.add_argument('--port', type=int, default=2575, help='Target port (default: 2575)')
    parser.add_argument('--count', type=int, default=100, help='Number of messages to send (default: 100)')
    parser.add_argument('--delay', type=float, default=0.1, help='Delay between messages in seconds (default: 0.1)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Show full message content')
    parser.add_argument('--no-wait-ack', action='store_true', help='Do not wait for ACK responses')
    
    args = parser.parse_args()
    
    print(f"HL7 ADT Message Sender")
    print(f"=" * 50)
    print(f"Target: {args.host}:{args.port}")
    print(f"Messages to send: {args.count}")
    print(f"Delay between messages: {args.delay}s")
    print(f"=" * 50)
    print()
    
    success_count = 0
    failure_count = 0
    
    try:
        # Create socket connection
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(10)
        sock.connect((args.host, args.port))
        print(f"Connected to {args.host}:{args.port}")
        print()
        
        for i in range(1, args.count + 1):
            message, control_id, event_type, patient_name = generate_hl7_message(i)
            
            print(f"[{i:03d}/{args.count}] Sending {event_type} for {patient_name} (ID: {control_id[:20]}...)")
            
            if args.verbose:
                print("-" * 40)
                print(message.replace('\r', '\n'))
                print("-" * 40)
            
            try:
                if args.no_wait_ack:
                    wrapped = wrap_mllp(message)
                    sock.sendall(wrapped)
                    print(f"         Sent (no ACK wait)")
                    success_count += 1
                else:
                    response = send_message(sock, message)
                    ack_success, ack_info = parse_ack(response)
                    
                    if ack_success:
                        print(f"         ACK: {ack_info}")
                        success_count += 1
                    else:
                        print(f"         NAK: {ack_info}")
                        failure_count += 1
                        
            except socket.timeout:
                print(f"         TIMEOUT waiting for response")
                failure_count += 1
            except Exception as e:
                print(f"         ERROR: {e}")
                failure_count += 1
            
            if args.delay > 0 and i < args.count:
                time.sleep(args.delay)
        
        sock.close()
        
    except ConnectionRefusedError:
        print(f"ERROR: Connection refused to {args.host}:{args.port}")
        print("Make sure the HL7 listener is running.")
        return 1
    except Exception as e:
        print(f"ERROR: {e}")
        return 1
    
    print()
    print(f"=" * 50)
    print(f"Summary:")
    print(f"  Total sent: {args.count}")
    print(f"  Successful: {success_count}")
    print(f"  Failed:     {failure_count}")
    print(f"=" * 50)
    
    return 0 if failure_count == 0 else 1


if __name__ == "__main__":
    exit(main())
