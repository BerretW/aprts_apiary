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

    // Kolik máme hotových a kolik prázdných čekajících
    let filledCount = hive.filledFrames;
    let emptyCount = hive.emptyFrames;
    let totalInstalled = filledCount + emptyCount;

    // Projdeme všechny sloty (např. 0, 1, 2, 3)
    for (let i = 0; i < hive.maxSlots; i++) {
        let slot = document.createElement('div');
        slot.className = 'frame-slot';
        
        // --- LOGIKA STAVŮ ---
        
        if (i < filledCount) {
            // 1. UŽ JE PLNÝ (Hotovo z dřívějška)
            slot.classList.add('full');
            slot.setAttribute('data-tooltip', 'Plný Medu (100%)');
            
        } else if (i === filledCount && emptyCount > 0) {
            // 2. PRÁVĚ SE PLNÍ (Tohle je ten aktivní!)
            // Pokud máme ještě prázdné rámky, ten první na řadě (index == filledCount) se plní.
            slot.classList.add('filling');
            
            // Nastavíme CSS proměnnou pro výšku hladiny (0-100%)
            slot.style.setProperty('--fill-pct', hive.progress + '%');
            
            // Tooltip ukazuje aktuální %
            slot.setAttribute('data-tooltip', `Plnění: ${hive.progress}%`);
            
        } else if (i < totalInstalled) {
            // 3. JE VLOŽENÝ, ALE ČEKÁ VE FRONTĚ (Prázdný)
            slot.classList.add('installed');
            slot.setAttribute('data-tooltip', 'Připraven (0%)');
            
        } else {
            // 4. CHYBÍ (Nevložený)
            slot.setAttribute('data-tooltip', 'Prázdný Slot');
        }
        
        visualContainer.appendChild(slot);
    }
    
    // Aktualizace textu pod rámky
    if(document.getElementById('lblFrames')) {
        document.getElementById('lblFrames').innerText = `Stav rámků: ${filledCount} Plné / ${totalInstalled} Vložené`;
    }

    // --- TLAČÍTKA ---
    // Logika tlačítek zůstává, jen CSS se postará o layout
    toggleBtn('btnInsertFrame', totalInstalled < hive.maxSlots);
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