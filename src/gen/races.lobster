// What each player was made from, as the game that made it wrote it down: the panels read a side's "name" and
// "family" from it, and saves keep it. Its own file so it stays the last global a save holds (a save's fields are
// in the order the globals are declared: lib/, gen/setup, gen/start, then this).
var su_races = []::JV
