function addNavItem(text, link) {
    let menu = document.querySelector(".navbar-nav");
    let listItem = document.createElement("li");
    listItem.classList.add("nav-item");

    let anchor = document.createElement("a");
    anchor.classList.add("nav-link");
    anchor.textContent = text;
    anchor.href = link;

    listItem.appendChild(anchor);
    menu.appendChild(listItem);
}

addNavItem("Server List", "djangofiles://serverlist");
addNavItem("Server Settings", "djangofiles://serversettings");

const navLinks = document.querySelectorAll('.nav-item')
const menuToggle = document.getElementById('navbarSupportedContent')
const bsCollapse = new bootstrap.Collapse(menuToggle, {toggle:false})
navLinks.forEach((l) => {
    l.addEventListener('click', () => { bsCollapse.toggle() })
})

document.body.getElementsByClassName("navbar")[0].style.paddingTop = "50px";
