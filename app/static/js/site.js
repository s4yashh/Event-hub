"use strict";

document.addEventListener("DOMContentLoaded", () => {
  const menuButton = document.querySelector(".menu-toggle");
  const nav = document.querySelector("#primary-nav");

  if (menuButton && nav) {
    menuButton.addEventListener("click", () => {
      const isOpen = menuButton.getAttribute("aria-expanded") === "true";
      menuButton.setAttribute("aria-expanded", String(!isOpen));
      menuButton.setAttribute("aria-label", isOpen ? "Open navigation" : "Close navigation");
      nav.classList.toggle("is-open", !isOpen);
    });

    nav.addEventListener("click", (event) => {
      if (event.target.closest("a")) {
        menuButton.setAttribute("aria-expanded", "false");
        menuButton.setAttribute("aria-label", "Open navigation");
        nav.classList.remove("is-open");
      }
    });
  }

  document.querySelectorAll(".toast").forEach((toast) => {
    const dismiss = () => {
      toast.classList.add("is-leaving");
      window.setTimeout(() => toast.remove(), 230);
    };
    toast.querySelector(".toast-close")?.addEventListener("click", dismiss);
    window.setTimeout(dismiss, 5600);
  });

  document.querySelectorAll("[data-loading-form]").forEach((form) => {
    form.addEventListener("submit", () => {
      const button = form.querySelector("button[type='submit']");
      if (!button || button.disabled) return;
      button.disabled = true;
      button.classList.add("button-loading");
      button.textContent = button.dataset.loadingLabel || "Working";
      button.setAttribute("aria-busy", "true");
    });
  });

  const search = document.querySelector("#event-search");
  const eventCards = Array.from(document.querySelectorAll("[data-event-card]"));
  const clubFilters = Array.from(document.querySelectorAll("[data-club-filter]"));
  const resultCount = document.querySelector("#event-result-count");
  const noEvents = document.querySelector("#no-results");
  let selectedClub = "all";

  function filterEvents() {
    if (!eventCards.length) return;
    const query = (search?.value || "").trim().toLocaleLowerCase();
    let visible = 0;
    eventCards.forEach((card) => {
      const matchesClub = selectedClub === "all" || card.dataset.club === selectedClub;
      const matchesQuery = !query || card.textContent.toLocaleLowerCase().includes(query);
      const show = matchesClub && matchesQuery;
      card.hidden = !show;
      if (show) visible += 1;
    });
    if (resultCount) resultCount.textContent = `${visible} ${visible === 1 ? "event" : "events"} to explore`;
    if (noEvents) noEvents.hidden = visible > 0;
  }

  search?.addEventListener("input", filterEvents);
  clubFilters.forEach((button) => {
    button.addEventListener("click", () => {
      selectedClub = button.dataset.clubFilter || "all";
      clubFilters.forEach((chip) => {
        const active = chip === button;
        chip.classList.toggle("is-selected", active);
        chip.setAttribute("aria-pressed", String(active));
      });
      filterEvents();
    });
  });

  document.querySelector("#clear-filters")?.addEventListener("click", () => {
    if (search) search.value = "";
    selectedClub = "all";
    clubFilters.forEach((chip) => {
      const active = chip.dataset.clubFilter === "all";
      chip.classList.toggle("is-selected", active);
      chip.setAttribute("aria-pressed", String(active));
    });
    filterEvents();
    search?.focus();
  });

  const ticketFilters = Array.from(document.querySelectorAll("[data-ticket-filter]"));
  const ticketRows = Array.from(document.querySelectorAll("[data-ticket-row]"));
  const noTickets = document.querySelector("#no-tickets");
  ticketFilters.forEach((button) => {
    button.addEventListener("click", () => {
      const filter = button.dataset.ticketFilter || "all";
      let visible = 0;
      ticketFilters.forEach((chip) => {
        const active = chip === button;
        chip.classList.toggle("is-selected", active);
        chip.setAttribute("aria-pressed", String(active));
      });
      ticketRows.forEach((row) => {
        const show = filter === "all" || row.dataset.status === filter;
        row.hidden = !show;
        if (show) visible += 1;
      });
      if (noTickets) noTickets.hidden = visible > 0;
    });
  });

