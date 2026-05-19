# Tapp Design Doc

## What it is

Tapp is an iphone app to store tallies. It is different than other tally apps because it is social. You can add friends and share your tallies with them. It is colorful and there is even a cool fireworks animation! Tapp is used by people who enjoy keeping track of things. It is a fun app and there are no notifications. The database is firebase.

There is no searching as I don't believe in that. If you have too many friends or tallies, you can find them on your own.



## Home Page

### What it does

The home page shows the user’s tallies, and is the landing page for the app.

### What it looks like

At the top right of the page is a small circular settings button (gear). Under settings is a two thirds screen width button (+). To its left is a small sort button (three bar). Under the add and sort buttons is a scrollable list of tallies. Each tally displays a name, a number, an owner (and if you aren’t permissed to change that tally, a lock).  
If you open the app and someone has updated a tally on your list, you’ll see their avatar appear briefly in the tally (by default, the most recently updated tallies appear first when reopening the app, but if there are too many updates, then you may not see earlier updates, and that is fine). If that tally was in firework mode, then you’ll also see fireworks in that tally box upon landing at the home page.

### Buttons

#### Settings

The settings button is a circular gear. When clicked, it takes the user to a settings page.

#### Add Tally

The add tally button is the same shape as a tally box, but is a little less long. It has a in the middle. Clicking it displays a pop up modal sheet that asks for a name and a 3-column table allowing the user to select how they dole out permissions for the tally (the three columns are username, view, and edit)

#### Sort

The sort button is small and fits between the left edge of the screen and the right edge of the add tally button. It is circular and has three bars. Clicking the sort button cycles between the four sorting modes: newest, oldest, last updated, and my tallies only. Last updated is the default sorting mode.

#### Tally

There may be many tallies on the home page (that’s the point of the app, after all). Each tally is a box spanning almost the entire width of the screen. Each tally displays its name (left), its count (right), and its owner (avatar and username) (bottom left corner) (with a lock if applicable). Tapping the tally button anywhere increases the count of the tally. Holding down the tally button takes the user to a larger screen for just that tally. Tallies may have different colors. There is no safeguard for two friends updating the tally at the same time. If it happens, it happens.

## Full Screen Tally

### What it does

Holding down a tally button from the home screen opens up the tally as its own screen. This screen has two purposes, giving the user a bigger hitbox to increase the count.

### What it looks like

At the top of the screen is the tally’s name. Under it, in big font, is the count. Arranged at the bottom of the screen are a bunch of small settings buttons.

### Buttons

#### Change Name

This button’s hitbox is the name at the top of the screen. Merely tapping this button however, won’t do anything. Holding down the button highlights the name and allows the user to type in a new one.

#### Change Number

This button’s hitbox is the number. Merely tapping this button, however, will increase the count. Holding down the button highlights the number and allows the user to type in a new number.

#### Color

The color button is a small color wheel or gradient. Clicking it shows a pop up allowing the user to select a color for the tally. This color is local.

#### Friends and Permissions

This button is small and circular and looks like two people. Clicking it shows a three column table where the user can adjust permissions for all their friends.

#### One time or scheduled resets

This button is a small circle and looks like a clock. Clicking it prompts the user to reset now, reset every day, reset every month, or reset every year. If one of the schedules has been selected in the past, then that option should already be highlighted. 

#### Fireworks

This button is a small circle with fireworks. Clicking it toggles it on or off. When it is on, then whenever the tally is increased, a firework animation will appear in the full screen tally, as well as in the tally box, for any user who has this tally.

#### Delete

The delete button is a small circle and looks like a trash can. Clicking it prompts the user if they’re sure they want to delete.

## Settings

### What it does

The settings screen allows users to change their settings, which include username, password, friends, number type, and theme.

### What it looks like

The settings page is a list of displayed settings with different buttons to change them.  
The settings are ordered thusly:  
Username: (username)  
Email: (email)  
Password: ()  
Friends:  
List of Friends  
Numbers (Arabic, Roman, or Stick)  
Theme (Light or Dark)  
(Considerable Space)  
Delete Account

### Buttons

#### Log Out

Asks to confirm, then logs the user out.

#### Password

Change password

#### Add Friend

This button is a box with normal sized text in it. Clicking it allows the user to type and enter a username. There is no search feature. If the username exists, the app will tell the user “success” otherwise it will tell the user “error.” Friends are not optional.

#### Numbers

This button will go after “Numbers: “ and will say the type of number (Arabic, Roman, Stick) in a box.

#### Theme

This button will go after “Theme: “ and will say the theme (Light, Dark) in a box.

#### Delete Account

This button will be a bright red box that says “Delete Account.” Clicking it will prompt the user once more to confirm this is what they want to do, then clicking confirm will delete the user’s account and log them out.