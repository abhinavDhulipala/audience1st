console.log("scriptloaded")

$("#donation").keypress(function(event) {
    if (String.fromCharCode(event.keyCode) === '-') {
        alert("You cannot donate a negative amount.")
        event.preventDefault();
    }
})