 # V1 Bugs

## Home Screen

### Bug

The tallies seem to sort every time any tally is updated. This leads to middle tallies (not bottom or top) moving around when they are pressed. It’s annoying. For example, suppose there are three tallies, “Pens,” “Sunglasses,” and “Scissors,” in that order on the home screen tally list. After adding a tally to “Sunglasses,” the middle tally, it first goes down to the bottom, so the order reads pens, scissors, sunglasses, then it goes to the top of the list. And the order reads sunglasses, pens, scissors. A preferable scenario would be that the list order doesn’t update every time one tally is changed.

### Solution

Have tallies sort only when the sort button is clicked, and not even on reentry to the app. There will be one sorting scheme, which the sort button toggles on and off: “sort by most recently updated, tie breaking by most recently created.” When sort is toggled off, the order of the tally list will be by creation, but not strictly. Two new features will be added, however: pins, and manual sorting. From the full screen tally, users will be able to pin tallies in the home screen, as many as they want. From the home homescreen, when sort is toggled off, users will see three bars on the side of the tally bar, which they can press to drag the bar up and down. The order that is shown is the order the homescreen will stay in and return to when the user leaves or toggles on sort.

### Example

add(sunglasses)  
add(pens)  
add(keys)  
// order in homescreen should be keys, pens, sunglasses  
tap(pens)  
// order should still be keys, pens, sunglasses  
toggleSort()  
// Sort=ON so order should now be pens, keys, sunglasses  
toggleSort()  
// sort \= OFF so order should now be back to keys, pens, sunglasses  
move(pens, 2\)  
// pens moved to last position, so order now keys, sunglasses, pens  
toggleSort()  
// pens, keys, sunglasses  
toggleSort()  
// keys, sunglasses, pens

## Colors

### Bug

Colors are more muted on screen than they are in the palette selector. They are probably better muted, but consistency is good.

### Solution

Anticipate color muting in the palette selector.

## Avatar

### Bug

Avatar color changes every time the user quits and reopens the app.

### Solution

Hold off on fixing this bug until later. As the avatar is not very developed as a feature yet.

## Development Setbacks

### Friends

Testing friends is difficult since I only have one phone to test with. Adding another account is a hassle. I tested adding a friend by manually creating a user in Firestore. It seems to work fine. In the future. Write automatic or manual tests to test this feature.

### Email

Sign in with email is hard to do and seems redundant. Change to a username and password only login.