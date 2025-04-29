# Design Choices
- Scene layers are traversed from top to bottom when handling events so that upper layers can block input / events from going into lower layers. This can be useful for when needing to display some layer over top of another (like a pause menu) and you do not want events bleeding into the lower layers
# Member Variables
# Public Functions
# Private Functions
# Other Related Topics