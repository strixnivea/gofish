# Imports
import mariadb
import struct
import sys

################################################
# LandSandBoat FFXI private server admins can  #
# use this script to generate fishing_db.lua   #
################################################

################################################
# Set user, password, host, port, and database #
# in 'try' below to match server settings      #
################################################

# Try to connect to MariaDB server
try:
  conn = mariadb.connect(
    user="user",
    password="pass",
    host="127.0.0.1",
    port=3306,
    database="dspdb"
  )
# Or else handle error
except mariadb.Error as e:
  print(f"Error connecting to MariaDB server: {e}")
  sys.exit(1)

# Get cursor
cur = conn.cursor()

# Open handle to output file
f = open("fishing_db.lua", "w")

# Generate a list of the tables of interest
table_list = ['area', 'bait', 'bait_affinity', 'catch', 'fish', 'group', 'mob', 'rod', 'zone']
table_list = ['fishing_'+x for x in table_list]

# Generate a dictionary of (zoneid, zonetype) pairs for a 'join' later
cur.execute("SELECT zoneid, zonetype FROM zone_settings")
zonetypes = {row[0]:row[1] for row in cur.fetchall()}

# Iterate through all the tables of interest and convert them to lua format
for table in table_list:
  # Grab a list of all the column names for current table
  cur.execute("SELECT column_name, column_type FROM information_schema.columns WHERE table_name='%s'" % table)
  column_list = cur.fetchall()

  # Grab all the rows in the table
  cur.execute("SELECT * FROM %s" % table)
  result = cur.fetchall()

  # Start a lua table definition
  f.write(table + " = {\n")

  # Iterate through all the rows in the table
  for row in result:
    # Define a row entry, which is a table itself
    entry = "{ "
    # Iterate over each column
    for i, col in enumerate(column_list):
      # Assume that an empty cell is nil
      if row[i] is None or row[i] == "":
        value = "nil"
      # Handle byte data as a special case
      elif str(row[i]).startswith("""b'"""):
        # If there is no data
        if str(row[i]) == """b''""":
          value = "nil"
        # Otherwise, parse the byte data as float
        else:
          # Define a value table for the float coordinates
          value = "{"
          # Work the magic
          decoded = [x[0] for x in struct.iter_unpack('<f', row[i])]
          # Count the (x,y,z) coordinate triplets in the decoded list of floats 
          count = int(len(decoded)/3)
          # Format the coordinates as a lua table
          for j in range(0,count):
            value += "{x=%.3f,z=%.3f}," % (decoded[j*3], decoded[j*3+2])
          # Cap the table listing the coordinates
          value = value[:-1] + "}"
      # Handle default case
      else:
        value = row[i]
        
      # Add quotes for strings and deal with apostrophes in value
      if "varchar" in col[1]:
        entry += "%s='%s', " % (col[0], value.replace("'","\\'"))
      # Handle non-string types
      else:
        entry += "%s=%s, " % (col[0], value)
        
    # Special case where data from zone_settings needs to 'join' to save space   
    if table == "fishing_zone":
      entry += "type=%d, " % (zonetypes[row[0]])
      
    # Cap the row entry definition and write it to file
    entry = entry[:-2] + " },"
    f.write("\t" + entry + "\n")

  # Cap the table definition
  f.write("};\n")

# Add the return statement to end of the file
f.write("\nreturn {\n")
for table in table_list:
  f.write("\t%s = %s,\n" % (table, table))
f.write("}")

# Close file and profit
f.close()

# Close MariaDB connection
conn.close()