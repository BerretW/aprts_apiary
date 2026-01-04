let currentApiaryId = null;
let currentHivesData = {};
let selectedHiveId = null;

window.addEventListener('message', function(event) {
    let data = event.data;

    if (data.action === "open") {
        currentApiaryId = data.apiaryId;
        currentHivesData = data.hives;
        
        // Zobrazit UI
        document.getElementById('app').style.display = 'flex';
        renderHiveList();
        
        // Logika tlačítka pro stavbu
        let count = Object.keys(currentHivesData).length;
        let btnBuild = document.getElementById('btnBuild');
        
        if (count >= data.maxHives) {
            btnBuild.innerText = "Kapacita Včelína Naplněna";
            btnBuild.disabled = true;
        } else {
            btnBuild.innerText = "+ Přistavět Úl";
            btnBuild.disabled = false;
        }
        
        // Reset výběru
        selectHive(null);
    }

    if (data.action === "update") {
        currentHivesData = data.hives;
        renderHiveList();
        if (selectedHiveId) {
            renderDetails(selectedHiveId);
        }
    }
});

function closeMenu() {
    $.post('https://aprts_apiary/close', JSON.stringify({}));
    document.getElementById('app').style.display = 'none';
}

document.onkeyup = function (data) {
    if (data.which == 27) {
        closeMenu();
    }
};

function renderHiveList() {
    let list = document.getElementById('hiveList');
    list.innerHTML = "";
    
    // Seřadíme klíče číselně (1, 2, 3...)
    let sortedKeys = Object.keys(currentHivesData).sort((a,b) => Number(a) - Number(b));

    sortedKeys.forEach(key => {
        let hive = currentHivesData[key];
        let div = document.createElement('div');
        div.className = 'hive-item';
        if (selectedHiveId == key) div.classList.add('active');
        
        // Ikona podle stavu
        let icon = "🐝";
        if (!hive.hasQueen) icon = "⚠️";
        if (hive.disease) icon = "🦠";

        div.innerHTML = `<span>Úl #${key}</span> <span>${icon}</span>`;
        div.onclick = () => selectHive(key);
        list.appendChild(div);
    });
}

function selectHive(id) {
    selectedHiveId = id;
    renderHiveList(); // Pro aktualizaci zvýraznění
    
    let details = document.getElementById('hiveDetails');
    let empty = document.getElementById('noSelection');

    if (!id) {
        details.style.display = 'none';
        empty.style.display = 'block';
        return;
    }

    empty.style.display = 'none';
    details.style.display = 'block';
    renderDetails(id);
}

function renderDetails(id) {
    let hive = currentHivesData[id];
    
    // Header
    document.getElementById('detailTitle').innerText = `Detail Úlu #${id}`;
    
    // Status
    let statusEl = document.getElementById('lblStatus');
    if (hive.disease) {
        statusEl.innerText = "⚠️ ZAMOŘENO: " + (hive.disease === "mites" ? "Roztoči" : hive.disease);
        statusEl.className = "status-badge status-bad";
    } else if (!hive.hasQueen) {
        statusEl.innerText = "⚠️ Chybí Královna";
        statusEl.className = "status-badge status-bad";
    } else {
        statusEl.innerText = "✔ V pořádku";
        statusEl.className = "status-badge status-ok";
    }

    // Queen
    let queenEl = document.getElementById('lblQueen');
    let queenAgeEl = document.getElementById('lblQueenAge');
    if (hive.hasQueen) {
        queenEl.innerText = "Aktivní";
        queenEl.style.color = "#2e7d32";
        queenAgeEl.style.display = "block";
        queenAgeEl.innerText = `Životnost: ${hive.queenLifespan} cyklů`;
    } else {
        queenEl.innerText = "Chybí";
        queenEl.style.color = "#c62828";
        queenAgeEl.style.display = "none";
    }

    // Population - ZAOKROUHLENÍ!
    let pop = Math.floor(hive.population); // Zde je oprava dlouhého čísla
    document.getElementById('lblPop').innerText = pop.toLocaleString(); // Přidá mezery pro tisíce

    // Bars
    let hp = Math.floor(hive.health);
    document.getElementById('valHealth').innerText = hp + "%";
    document.getElementById('barHealth').style.width = hp + "%";

    let prod = Math.floor(hive.progress);
    document.getElementById('valProd').innerText = prod + "%";
    document.getElementById('barProd').style.width = prod + "%";
    
    document.getElementById('lblFrames').innerText = `${hive.filledFrames} / ${hive.maxSlots}`;


let visualContainer = document.getElementById('visualHive');
    visualContainer.innerHTML = ''; 

    // Počítadla pro smyčku
    let fullCount = hive.filledFrames;
    let emptyCount = hive.emptyFrames; // Rámky vložené, ale bez medu

    for (let i = 0; i < hive.maxSlots; i++) {
        let slot = document.createElement('div');
        slot.className = 'frame-slot';
        
        if (fullCount > 0) {
            // Priorita 1: Plné rámky
            slot.classList.add('full');
            fullCount--;
        } else if (emptyCount > 0) {
            // Priorita 2: Vložené prázdné rámky
            slot.classList.add('installed');
            emptyCount--;
        } else {
            // Zbytek: Prázdné sloty (ničím neoznačujeme, zůstane dashed border)
        }
        
        visualContainer.appendChild(slot);
    }
    
    // Textový přehled (aktualizovaný)
    let totalInstalled = hive.filledFrames + hive.emptyFrames;
    if(document.getElementById('lblFrames')) {
        document.getElementById('lblFrames').innerText = `${hive.filledFrames} Plné / ${totalInstalled} Vložené`;
    }

    // Buttons Logic
    // Inventář vždy povolen
    
toggleBtn('btnInsertFrame', totalInstalled < hive.maxSlots);
    
    // Vyjmout lze jen plné (nebo bychom mohli dovolit vyjmout i prázdné, ale zatím řešíme sklizeň)
    toggleBtn('btnHarvest', hive.filledFrames > 0);
    
    toggleBtn('btnQueen', !hive.hasQueen);
    toggleBtn('btnCure', hive.disease != null);
}

function toggleBtn(id, state) {
    let btn = document.getElementById(id);
    btn.disabled = !state;
}

function action(actName) {
    if (actName !== 'build' && !selectedHiveId) return;

    $.post(`https://aprts_apiary/${actName}`, JSON.stringify({
        apiaryId: currentApiaryId,
        hiveId: selectedHiveId
    }));
}