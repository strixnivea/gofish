# GoFish
An Ashita v4 addon to simulate the LandSandBoat ([LSB]) implementation of FFXI fishing
### Features
- Determines catchable fish and calculates the corresponding catch chances
- Calculates the chances to catch an item, a mob, and no catch
- Calculates the chances that a fish can break the line or the poll
- Calculates catch loss chances based on catch size and player skill
- Calculates the Vana'diel month, hour, and moon phase for adjusting catch chances
- Calculates the chances that a fish will provide a skillup
- Adjusts catch chances based on weather
### How it works
The script updates whenever the player... 
- Starts fishing
- Changes zones
- Changes equipment
- Loads the addon
- User sends 'update' command
### Possible updates
- Calculate the chances that a golden arrow will appear during minigame
- Moghancement adjustments (if LSB implements them and client has access)
- Allow user to adjust font scaling
- Allow user to choose which columns to display in catch table
### Things it will not do
- Automate anything
- Determine if the fish pool is empty (client likely does not have access)
- Calculate anything for NMs or quest items

[LSB]: <https://github.com/LandSandBoat/server>
