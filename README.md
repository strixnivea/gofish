# GoFish
An Ashita v4 addon to simulate the LandSandBoat ([LSB]) implementation of FFXI fishing
### Features
- Determines catchable fish and calculates the corresponding catch chances
- Calculates the chances to catch an item, a mob, and no catch
- Calculates the Vana'diel month, hour, and moon phase for adjusting catch chances
- Adjusts catch chances based on weather
### How it works
The script updates whenever the player... 
- Starts fishing
- Changes zones
- Changes equipment
- Loads the addon
### What it still needs
- Determine additional skill from equipped gear
- Adjust hook chance of a fish based on Shellfish Affinity
- Adjust item chances using Fishing Apron
- Adjust fish chances for Poor Fish Bait flag
- Command to force the script to update chances
### Possible updates
- Calculate the chances that a fish can break the line or the poll
- Calculate the chances that a fish will provide a skillup
- Calculate the chances that a golden arrow will appear during minigame
- Calculate catch loss chances based on catch size and player skill
- Moghancement adjustments (if LSB implements them and client has access)
- Allow user to adjust font scaling
### Things it will not do
- Automate anything
- Determine if the fish pool is empty (client likely does not have access)
- Calculate anything for NMs or quest items

[LSB]: <https://github.com/LandSandBoat/server>
