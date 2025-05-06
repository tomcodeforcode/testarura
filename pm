from flask import Flask, request, redirect, url_for, session, render_template 
import requests
import time
import json
import os
from dotenv import load_dotenv, set_key
from flask import jsonify , session
from flask_cors import CORS  # Import CORS
import psycopg2
import sqlite3 

app = Flask(__name__)
CORS(app)
app.secret_key = os.getenv('SECRET_KEY', 'default_secret_key')

# Load environment variables from .env file
load_dotenv()

#http://localhost:5000/callback 


DATABASE_URL = os.getenv('DATABASE_URL')  # Set this in your environment or .env file





# Replace these with your actual Zoho details
client_id = os.getenv('ZOHO_CLIENT_ID')
client_secret = os.getenv('ZOHO_CLIENT_SECRET')
redirect_uri = os.getenv('ZOHO_REDIRECT_URI')
auth_url = 'https://accounts.zoho.com/oauth/v2/auth'
token_url = 'https://accounts.zoho.com/oauth/v2/token'
api_url = 'https://people.zoho.com/people/api/forms/employee/getRecords'

@app.route('/')
def index():
    scope = 'ZOHOPEOPLE.forms.ALL'
    auth_request_url = f"{auth_url}?scope={scope}&client_id={client_id}&response_type=code&redirect_uri={redirect_uri}&access_type=offline"
    return redirect(auth_request_url)

@app.route('/callback')
def callback():
    code = request.args.get('code')
    if not code:
        return 'Error: No code found in the callback URL', 400

    token_data = {
        'code': code,
        'client_id': client_id,
        'client_secret': client_secret,
        'redirect_uri': redirect_uri,
        'grant_type': 'authorization_code'
    }

    response = requests.post(token_url, data=token_data)
    response_json = response.json()

    print("get this work done",response_json)
    if response.status_code != 200:
        return f"Error: {response_json.get('error', 'Unknown error')}", 400
    
    access_token = response_json.get('access_token')
    if not access_token:
        return 'Error: Access token not found', 400
 
   
    set_key('.env', 'ZOHO_ACCESS_TOKEN', access_token)

    # Store the token in session for immediate use
    session['access_token'] = access_token
    return redirect(url_for('fetch_bulk_records'))

@app.route('/fetch_bulk_records')
def fetch_bulk_records():
    access_token = session.get('access_token') or os.getenv('ZOHO_ACCESS_TOKEN')
    if not access_token:
        return 'Error: Access token not found', 400

    headers = {'Authorization': f'Zoho-oauthtoken {access_token}', 'Content-Type': 'application/json'}
    params = {'sIndex': 1, 'limit': 100}
    all_records = []

    while True:
        response = requests.get(api_url, headers=headers, params=params)
        response_json = response.json()

        print("get the name",response_json)    
        if response.status_code == 200:
            employee_data = response_json.get("response", {}).get("result", [])

            if not employee_data:
                break

            all_records.extend(employee_data)
            params['sIndex'] += 100  # Move to the next set of records
        elif response.status_code == 429:
            retry_after = int(response.headers.get('Retry-After', 60))
            time.sleep(retry_after)
        else:
            return f"Error fetching records: {json.dumps(response_json)}"

    # Format the records to a structured JSON format before passing to template
    formatted_records = []
    for record in all_records:
        formatted_record = {
            "records": record,
            'EmployeeID': record.get('Employee_ID', 'N/A'),
            'FirstName': record.get('First_Name', 'N/A'),
            'LastName': record.get('Last_Name', 'N/A'),
            'EmailID': record.get('Email_ID', 'N/A'),
            'Department': record.get('Department', 'N/A'),
            'Photo': record.get('Photo', 'default.jpg'),  # Default photo if not available
        }

        print('let go',formatted_record)
        formatted_records.append(formatted_record)

    return jsonify(formatted_records)
    return render_template('employees.html', employees=formatted_records)

@app.route('/public/employees')
def public_employees():
    # Use the stored access token from .env
    access_token = os.getenv('ZOHO_ACCESS_TOKEN')

    if not access_token:
        return 'Error: Access token not found', 400

    headers = {'Authorization': f'Zoho-oauthtoken {access_token}', 'Content-Type': 'application/json'}
    params = {'sIndex': 1, 'limit': 100}
    all_records = []

    # Fetch employee data
    while True:
        response = requests.get(api_url, headers=headers, params=params)
        response_json = response.json()

        if response.status_code == 200:
            employee_data = response_json.get("response", {}).get("result", [])

            if not employee_data:
                break

            all_records.extend(employee_data)
            params['sIndex'] += 100  # Move to the next set of records
        elif response.status_code == 429:
            retry_after = int(response.headers.get('Retry-After', 60))
            time.sleep(retry_after)
        else:
            return f"Error fetching records: {json.dumps(response_json)}"

    # Format the records for rendering
    formatted_records = []
    for record in all_records:
        formatted_record = {
             "records": record,
            'EmployeeID': record.get('Employee_ID', 'N/A'),
            'FirstName': record.get('First_Name', 'N/A'),
            'LastName': record.get('Last_Name', 'N/A'),
            'EmailID': record.get('Email_ID', 'N/A'),
            'Department': record.get('Department', 'N/A'),
            'Photo': record.get('Photo', 'default.jpg'),
        }
        formatted_records.append(formatted_record)

    # Render the public employee data
    return render_template('public_employees.html', employees=formatted_records)


@app.route('/employee/<employee_id>')
def fetch_employee(employee_id):
    # Retrieve the access token from session or .env
    access_token = session.get('access_token') or os.getenv('ZOHO_ACCESS_TOKEN')
    if not access_token:
        return 'Error: Access token not found', 400

    # Set up headers for the API request
    headers = {'Authorization': f'Zoho-oauthtoken {access_token}', 'Content-Type': 'application/json'}
    
    # Send the GET request to the Zoho API
    url = f"{api_url}?criteria=Employee_ID=='{employee_id}'"
    response = requests.get(url, headers=headers)
    response_json = response.json()

    if response.status_code == 200:
        # Get the employee data from the response
        employee_data = response_json.get("response", {}).get("result", [])
        
        # Check if the employee_data contains the employee_id you're interested in
        for record in employee_data:
            # Assuming the employee ID is the key in the dictionary (based on the structure of the data)
            if employee_id in record:
                # Print the data of the specific employee
                
                jsondata = jsonify(record[employee_id])  # Optionally return as JSON response
                employee_details = record[employee_id]
                
                # Return the employee details to the template
                return render_template('employee_detail.html', employees=employee_details)
        
        # If no matching employee was found
        return 'Error: Employee not found', 404
    else:
        return 'Error: Unable to fetch employee data', 500



@app.route('/api/employees', methods=['GET'])
def fetch_bulk_recordsx():
    access_token = session.get('access_token') or os.getenv('ZOHO_ACCESS_TOKEN')
    if not access_token:
        return 'Error: Access token not found', 400

    headers = {'Authorization': f'Zoho-oauthtoken {access_token}', 'Content-Type': 'application/json'}
    params = {'sIndex': 1, 'limit': 100}
    all_records = []

    while True:
        response = requests.get(api_url, headers=headers, params=params)
        response_json = response.json()

        if response.status_code == 200:
            employee_data = response_json.get("response", {}).get("result", [])

            if not employee_data:
                break

            all_records.extend(employee_data)
            params['sIndex'] += 100  # Move to the next set of records
        elif response.status_code == 429:
            retry_after = int(response.headers.get('Retry-After', 60))
            time.sleep(retry_after)
        else:
            return f"Error fetching records: {json.dumps(response_json)}"

    # Format the records to a structured JSON format before passing to template
    formatted_records = []
    for record in all_records:
        formatted_record = {
            "records": record,
            'EmployeeID': record.get('Employee_ID', 'N/A'),
            'FirstName': record.get('First_Name', 'N/A'),
            'LastName': record.get('Last_Name', 'N/A'),
            'EmailID': record.get('Email_ID', 'N/A'),
            'Department': record.get('Department', 'N/A'),
            'Photo': record.get('Photo', 'default.jpg'),  # Default photo if not available
        }
        formatted_records.append(formatted_record)

    return jsonify(formatted_records)


@app.route('/api/hello', methods=['GET'])
def hello_world():
    return jsonify({'message': 'Hello World'})



# Database URL (ensure this is set correctly for Onrender)
DATABASE_URL = os.getenv('DATABASE_URL')  # Set this in your environment or .env file

 
# Function to get database connection
import psycopg2
import psycopg2

def get_db_connection():
    try:
        # Connect to the PostgreSQL database
        conn = psycopg2.connect(DATABASE_URL, sslmode='require')
        cursor = conn.cursor()
        
        # Alter the table and add new columns if they do not exist
        # cursor.execute("""
        #     -- Alter the employee_id column to VARCHAR(100)
        #     ALTER TABLE employee_table
        #     ALTER COLUMN employee_id TYPE VARCHAR(100);

        #     -- Check if the column "about" exists and alter it to VARCHAR(10000) if it does
        #     DO $$
        #     BEGIN
        #         IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
        #                        WHERE table_name = 'employee_table' AND column_name = 'about') THEN
        #             ALTER TABLE employee_table ADD COLUMN about TEXT;
        #         END IF;
        #     END $$;

        #     -- Change the "about" column data type to VARCHAR(10000)
        #     ALTER TABLE employee_table
        #     ALTER COLUMN about TYPE VARCHAR(10000);

        #     -- Add the "phone" column if it doesn't exist
        #     DO $$
        #     BEGIN
        #         IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
        #                        WHERE table_name = 'employee_table' AND column_name = 'phone') THEN
        #             ALTER TABLE employee_table ADD COLUMN phone VARCHAR(15);
        #         END IF;
        #     END $$;

        #     -- Add the "designation" column if it doesn't exist
        #     DO $$
        #     BEGIN
        #         IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
        #                        WHERE table_name = 'employee_table' AND column_name = 'designation') THEN
        #             ALTER TABLE employee_table ADD COLUMN designation VARCHAR(100);
        #         END IF;
        #     END $$;
        # """)
        conn.commit()  # Commit the changes
        
        return conn
    except Exception as e:
        print(f"Error connecting to database: {e}")
        return None




# @app.route('/fetch_bulk_records')
# def fetch_bulk_records():
#     access_token = session.get('access_token') or os.getenv('ZOHO_ACCESS_TOKEN')
#     if not access_token:
#         return 'Error: Access token not found', 400

#     headers = {'Authorization': f'Zoho-oauthtoken {access_token}', 'Content-Type': 'application/json'}
#     params = {'sIndex': 1, 'limit': 100}
#     all_records = []

#     while True:
#         response = requests.get(api_url, headers=headers, params=params)
#         response_json = response.json()

#         if response.status_code == 200:
#             employee_data = response_json.get("response", {}).get("result", [])

#             if not employee_data:
#                 break

#             all_records.extend(employee_data)
#             params['sIndex'] += 100  # Move to the next set of records
#         elif response.status_code == 429:
#             retry_after = int(response.headers.get('Retry-After', 60))
#             time.sleep(retry_after)
#         else:
#             return f"Error fetching records: {json.dumps(response_json)}"

#     # print(all_records)
#     # Get DB connection
#     conn = get_db_connection()
#     if not conn:
#         return 'Error: Could not connect to the database', 500

#     cursor = conn.cursor()

#     # List to hold all formatted records to return later
#     formatted_records = []

#     for record in all_records:
#         formatted_record = {
#             "records": record,  # Assuming `record` is a dictionary
#         }

#         # Iterate through all keys in 'records'
#         for employee_key, employee_data_list in formatted_record['records'].items():
#             if isinstance(employee_data_list, list):  # Ensure it's a list
#                 # Iterate over each employee record in the list
#                 for employee_data in employee_data_list:
#                     # Extracting specific information for each employee

                   
#                     employee_id = employee_data.get('EmployeeID', 'N/A')  # Can now handle alphanumeric
#                     first_name = employee_data.get('FirstName', 'N/A')
#                     last_name = employee_data.get('LastName', 'N/A')
#                     email_id = employee_data.get('EmailID', 'N/A')
#                     photo_url = employee_data.get('Photo', 'default.jpg')
#                     photo_download_url = employee_data.get('Photo_downloadUrl', 'default.jpg')
#                     about = employee_data.get('AboutMe', 'N/A'),
#                     designation = employee_data.get('Designation', 'N/A'),
#                     phone = employee_data.get('Work_phone', 'N/A')

#                     # Printing the extracted information for each employee
#                     print(f"Employee ID: {employee_id}")
#                     print(f"First Name: {first_name}")
#                     print(f"Last Name: {last_name}")
#                     print(f"Email ID: {email_id}")
#                     print(f"Photo URL: {photo_url}")
                    
#                     print(f"about: {about}")
#                     print(f"Designation: {designation}")
#                     print(f"about: {about}")
#                     print(f"phone: {phone}")
#                     print("-----")  # Separator between records

#                     # Add the employee data to the list to return it
#                     formatted_records.append({
#                         'EmployeeID': employee_id,
#                         'FirstName': first_name,
#                         'LastName': last_name,
#                         'EmailID': email_id,
#                         'PhotoURL': photo_url,
#                         'PhotoURL1': photo_download_url,
#                         'about': about,
#                         'Designation': designation ,
#                         'Work_phone' : phone ,
#                     })

#                     # Insert or update the record in the employee_table
#                     cursor.execute("""
#                     INSERT INTO employee_table (employee_id, first_name, last_name, email_id, photo_downloadUrl, photo_url , about ,designation , phone )
#                     VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
#                     ON CONFLICT (employee_id) 
#                     DO UPDATE SET
#                         first_name = EXCLUDED.first_name,
#                         last_name = EXCLUDED.last_name,
#                         email_id = EXCLUDED.email_id,
#                         photo_downloadUrl = EXCLUDED.photo_downloadUrl,
#                         photo_url = EXCLUDED.photo_url,
#                         about = EXCLUDED.about,
#                         designation = EXCLUDED.designation,
#                         phone = EXCLUDED.phone;
#                     """, (employee_id, first_name, last_name, email_id, photo_download_url, photo_url, about ,designation , phone))
#                     conn.commit()

#     # Close the cursor and connection
#     cursor.close()
#     conn.close()

#     # Return all records
#     return jsonify(formatted_records)





@app.route('/api/employeesfetch', methods=['GET'])
def get_all_employees():
    # Get DB connection
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Could not connect to the database'}), 500

    cursor = conn.cursor()

    # Query to fetch all employee records from employee_table
    cursor.execute('SELECT employee_id, first_name, last_name, email_id, photo_url ,photo_downloadUrl,about,designation , phone FROM employee_table;')

    # Fetch all records
    employees = cursor.fetchall()

    print(employees)
    # Format the records into a list of dictionaries
    formatted_employees = []
    for employee in employees:
        formatted_employees.append({
            'EmployeeID': employee[0],  # Assuming employee_id is the first column
            'FirstName': employee[1],   # Assuming first_name is the second column
            'LastName': employee[2],    # Assuming last_name is the third column
            'EmailID': employee[3],     # Assuming email_id is the fourth column
            'PhotoURL': employee[4],    # Assuming photo_url is the fifth column
             'photo_downloadUrl': employee[5], 
               'about': employee[6], 
               'designation': employee[7], 
               'phone': employee[8], 
        })

    # Close the cursor and connection
    cursor.close()
    conn.close()

    # Return all employee records as JSON
    return jsonify(formatted_employees)









@app.route('/fetch_employee_details/<employee_id>', methods=['GET'])
def get_employee_by_id(employee_id):
    # Get DB connection
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Could not connect to the database'}), 500

    cursor = conn.cursor()

    # Query to fetch the employee record based on the provided employee_id
    cursor.execute('SELECT employee_id, first_name, last_name, email_id, photo_url, photo_downloadUrl, about, designation, phone FROM employee_table WHERE employee_id = %s;', (employee_id,))

    # Fetch the record
    employee = cursor.fetchone()

    # If no employee is found, return an error message
    if employee is None:
        return jsonify({'error': 'Employee not found'}), 404

    # Format the record into a dictionary
    formatted_employee = {
        'EmployeeID': employee[0],  
        'FirstName': employee[1],   
        'LastName': employee[2],    
        'EmailID': employee[3],     
        'PhotoURL': employee[4],    
        'photo_downloadUrl': employee[5], 
        'about': employee[6], 
        'designation': employee[7], 
        'phone': employee[8], 
    }

    # Close the cursor and connection
    cursor.close()
    conn.close()

    # Return the employee record as JSON
    return jsonify(formatted_employee)







# If you want to render the records on an HTML page:
# return render_template('employees.html', employees=formatted_records)

# return render_template('employees.html', employees=formatted_records)



  # Set this in your environment or .env file

# def get_db_connectionp():
#     # Make sure that DATABASE_URL is properly set
#     if not DATABASE_URL:
#         raise ValueError("DATABASE_URL is not set")

#     conn = sqlite3.connect(DATABASE_URL)  # Connect to the SQLite database using the DATABASE_URL
#     conn.row_factory = sqlite3.Row  # This allows access to rows like dictionaries
#     return conn

# @app.route('/api/employees', methods=['GET'])
# def get_all_employees():
#     try:
#         # Get DB connection
#         conn = get_db_connectionp()

#         # Query to fetch all employees
#         cursor = conn.cursor()
#         cursor.execute('SELECT * FROM employee_table;')

#         # Fetch all records
#         employees = cursor.fetchall()

#         # Format the records into a dictionary of employees keyed by EmployeeID
#         formatted_employees = {}
#         for employee in employees:
#             # Extract the EmployeeID (assuming it's a column in the table)
#             employee_id = employee['EmployeeID']
#             formatted_employees[employee_id] = {
#                 'EmployeeID': employee['EmployeeID'],
#                 'FirstName': employee['FirstName'],
#                 'LastName': employee['LastName'],
#                 'EmailID': employee['EmailID'],
#                 'Photo': employee['Photo'],
#                 'Role': employee['Role'],
#                 # You can add any other fields you need here
#             }

#         # Close the cursor and connection
#         cursor.close()
#         conn.close()

#         # Return all employee records as JSON
#         return jsonify({'records': formatted_employees})
    
#     except Exception as e:
#         # Handle exceptions (e.g., DB connection error, query error)
#         return jsonify({'error': f'Error: {str(e)}'}), 500


# @app.route('/fetch_employee_details/<employee_id>', methods=['GET'])
# def fetch_employee_details(employee_id):
#     # Get access token from session or environment
#     access_token = session.get('access_token') or os.getenv('ZOHO_ACCESS_TOKEN')
#     if not access_token:
#         return 'Error: Access token not found', 400

#     headers = {'Authorization': f'Zoho-oauthtoken {access_token}', 'Content-Type': 'application/json'}
 
#     response = requests.get(api_url, headers=headers)

#     print("hello" ,response)

#     response_json = response.json()

#     if response.status_code == 200:
#         employee_data = response_json.get("response", {}).get("result", [{}])[0]
#         print("hello" ,employee_data)
#         # Extracting relevant fields from the employee data
#         employee_id = employee_data.get('EmployeeID', 'N/A')
#         first_name = employee_data.get('FirstName', 'N/A')
#         last_name = employee_data.get('LastName', 'N/A')
#         email_id = employee_data.get('EmailID', 'N/A')
#         photo_url = employee_data.get('Photo', 'default.jpg')
#         photo_download_url = employee_data.get('Photo_downloadUrl', 'default.jpg')
#         about = employee_data.get('AboutMe', 'N/A')
#         designation = employee_data.get('Designation', 'N/A')
#         phone = employee_data.get('Work_phone', 'N/A')

#         # Format the employee data
#         formatted_employee = {
#             'EmployeeID': employee_id,
#             'FirstName': first_name,
#             'LastName': last_name,
#             'EmailID': email_id,
#             'PhotoURL': photo_url,
#             'PhotoURL1': photo_download_url,
#             'About': about,
#             'Designation': designation,
#             'Work_phone': phone
#         }

#         # Return the formatted employee data as a JSON response
#         return jsonify(formatted_employee)

#     elif response.status_code == 429:
#         retry_after = int(response.headers.get('Retry-After', 60))
#         time.sleep(retry_after)
#         return fetch_employee_details(employee_id)  # Retry fetching the employee data after waiting

#     else:
#         return f"Error fetching employee data: {json.dumps(response_json)}", 500



if __name__ == '__main__':
    app.run(debug=True, port=5000)


...................................................


SECRET_KEY=your_flask_secret_key
ZOHO_CLIENT_ID= 1000.LEIGXXSUCX9JKJG9ELTIQ5X9E56DLY
ZOHO_CLIENT_SECRET=ebdd6fc02d4be8a143f0cc56a5e0c1dcc1340f5859


ZOHO_REDIRECT_URI=http://43.205.206.134:5000/callback 
ZOHO_ACCESS_TOKEN='1000.90c8e28fc69fae16bc8415b5a3451e98.b945c50ec151165e7be3035a52ab9949'
ZOHO_REFRESH_TOKEN=your_refresh_token_here
DATABASE_URL=postgresql://mydatabase_z7li_user:xt9wmvY3DKfy0nSoufaetzioCF1f9TKq@dpg-cugrik3v2p9s73cmr46g-a.oregon-postgres.render.com:5432/mydatabase_z7li




............................................



requests>=2.18.0,<3.0

psycopg2-binary==2.9.3   


werkzeug==2.0.3

flask==2.1.1
flask_cors==5.0.0
gunicorn==20.1.0
python-dotenv==0.21.0
nibabel==5.3.2
streamlit==1.41.1
pyxnat==1.6.2
google-cloud-storage==2.19.0
google-api-core==2.24.0
wheel==0.45.1
watchdog==6.0.0



....................................................


Procfile

web: gunicorn app:app


//////////////////////////////////////


<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Employee Records</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        /* Custom Styles */
        .card {
            background-color: #fff;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
            border-radius: 8px;
            overflow: hidden;
        }
        .card-header {
            background-color: #f3f4f6;
            padding: 20px;
        }
        .card-body {
            padding: 20px;
        }
    </style>
</head>

<body class="bg-gray-100 font-sans antialiased p-8">

    <h1 class="text-3xl font-bold text-center mb-8">Employee Records</h1>

    <!-- Table for Employee Data -->
    <table class="min-w-full table-auto bg-white shadow-md rounded-lg">
        <thead>
            <tr class="bg-gray-200">
                <th class="px-4 py-2">First Name</th>
                <th class="px-4 py-2">Last Name</th>
                <th class="px-4 py-2">EmailID</th>
                <th class="px-4 py-2">About Me</th>
                <th class="px-4 py-2">Work Phone</th>
            </tr>
        </thead>
        <tbody>
            {% for employee in employees %}
                <tr class="border-b">
                    <td class="px-4 py-2">{{ employee.FirstName }}</td>
                    <td class="px-4 py-2">{{ employee.LastName }}</td>
                    <td class="px-4 py-2">{{ employee.EmailID }}</td>
                    <td class="px-4 py-2">{{ employee.AboutMe }}</td>
                    <td class="px-4 py-2">{{ employee.Work_phone }}</td>
                </tr>
            {% endfor %}
        </tbody>
    </table>

</body>
</html>


//////////////////////////


<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Employee Records</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        /* Custom Styles */
        .card {
            background-color: #fff;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
            border-radius: 8px;
            overflow: hidden;
        }
        .card-header {
            background-color: #f3f4f6;
            padding: 20px;
        }
        .card-body {
            padding: 20px;
        }
    </style>
</head>


<body class="bg-gray-100 font-sans antialiased p-8">


    
    <table>
        <thead>
            <tr>
                <th>Data</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                {% for employee in employees %}
                    <td>{{ employee }}</td>
                {% endfor %}
            </tr>
        </tbody>
    </table>
    <h1 class="text-3xl font-bold text-center mb-8">Employee Records</h1>


    
   
    <div class="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
        {% for employee in employees %}
        {% for record_key, record_value in employee.records.items() %}
        <div class="card max-w-sm mx-auto">
            <div class="card-header flex items-center space-x-4">
                <!-- Employee Photo -->
                <div class="flex-shrink-0">
                    {% if record_value[0].Photo_downloadUrl %}
                    <img 
                        src="{{ record_value[0].Photo_downloadUrl }}" 
                        alt="Employee Photo" 
                        class="w-16 h-16 rounded-full object-cover"
                        onerror="this.onerror=null; this.src='https://people.zoho.com/cloudi/viewPhoto?erecno={{ record_value[0].Zoho_ID }}&mode=1&avatarid=35';"
                    >
                    {% else %}
                    <img 
                        src="https://people.zoho.com/cloudi/viewPhoto?erecno={{ record_value[0].Zoho_ID }}&mode=1&avatarid=35" 
                        alt="Employee Photo" 
                        class="w-16 h-16 rounded-full object-cover"
                    >
                    {% endif %}
                </div>
                <div class="text-gray-700">
                    <h2 class="font-semibold text-xl">{{ record_value[0].FirstName }} {{ record_value[0].LastName }}</h2>
                    <p class="text-sm text-gray-500">{{ record_value[0].Designation }}</p>
                </div>
            </div>

            <div class="card-body space-y-4">
                <!-- Email -->
                <p class="text-gray-700"><strong>Email:</strong> {{ record_value[0].EmailID }}</p>

                <!-- Work Phone -->
                <p class="text-gray-700"><strong>Phone:</strong> {{ record_value[0].Work_phone }}</p>

                <!-- About Me -->
                <p class="text-gray-700"><strong>About:</strong> {{ record_value[0].AboutMe }}</p>
            </div>
        </div>
        {% endfor %}
        {% endfor %}
    </div>

    
    <script type="application/json" id="employee-data">
        {{ employees | tojson }}
    </script>

</body>
</html>



