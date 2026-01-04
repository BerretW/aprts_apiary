let currentApiaryId = null;
let currentHivesData = {};
let selectedHiveId = null;
let geneticsChart = null;
// Naslouchání zprávám z LUA
window.addEventListener('message', function (event) {
    let data = event.data;

    if (data.action === "open") {
        currentApiaryId = data.apiaryId;
        currentHivesData = data.hives;

        // Zobrazit UI
        document.getElementById('app').style.display = 'flex';

        // Render seznamu a tlačítka pro stavbu
        updateLeftPage(data.maxHives);

        // Reset výběru
        selectHive(null);
    }
    if (data.action === "close") {
        closeMenu();
    }
    if (data.action === "update") {
        currentHivesData = data.hives;
        // Zjistit maxHives (pokud není posláno, odhadneme z UI nebo necháme)
        // Ideálně by update event měl posílat i maxHives, ale pro teď jen překreslíme list
        updateLeftPage(null);

        if (selectedHiveId && currentHivesData[selectedHiveId]) {
            renderDetails(selectedHiveId);
        } else if (selectedHiveId && !currentHivesData[selectedHiveId]) {
            // Úl byl smazán nebo neexistuje
            selectHive(null);
        }
    }
    if (data.action === "openMicroscope") {
        document.getElementById('microscopeApp').style.display = 'flex';
        renderRadarChart(data.genetics);
        document.getElementById('geneGen').innerText = data.genetics.generation || 1;

        // Výpočet celkového skóre (Average)
        let total =
            data.genetics.productivity +
            data.genetics.fertility +
            data.genetics.resilience +
            data.genetics.adaptability +
            (100 - data.genetics.aggression); // Agrese je inverzní

        let avg = Math.floor(total / 5);
        let grade = "F";
        if (avg > 80) grade = "S (Legendární)";
        else if (avg > 70) grade = "A (Vynikající)";
        else if (avg > 50) grade = "B (Průměr)";
        else grade = "C (Slabé)";

        document.getElementById('geneQuality').innerText = grade;
    }
    if (data.action === "closeMicroscope") {
        closeMicroscope();
    }
});
function closeMicroscope() {
    document.getElementById('microscopeApp').style.display = 'none';
    $.post('https://aprts_apiary/closeMicroscope', JSON.stringify({}));
}
function renderLogs(logs) {
    let container = document.getElementById('hiveLogs');
    container.innerHTML = "";

    if (!logs || logs.length === 0) {
        container.innerHTML = "<li style='justify-content:center; opacity:0.5;'>Žádné záznamy</li>";
        return;
    }

    logs.forEach(log => {
        let li = document.createElement('li');
        li.innerHTML = `<span class="log-time">${log.time}</span> <span class="log-msg">${log.msg}</span>`;
        container.appendChild(li);
    });
}
function renderRadarChart(genes) {
    const ctx = document.getElementById('geneticsChart').getContext('2d');

    // Zničit starý graf, pokud existuje
    if (geneticsChart) {
        geneticsChart.destroy();
    }

    // Chart.js konfigurace
    geneticsChart = new Chart(ctx, {
        type: 'radar',
        data: {
            labels: [
                'Produktivita',
                'Plodnost',
                'Odolnost',
                'Adaptabilita',
                'Klidnost (Non-Agrese)', // Obrátíme Agresi, aby "více = lépe" pro graf
                'Životnost'
            ],
            datasets: [{
                label: 'Genetický Profil',
                data: [
                    genes.productivity,
                    genes.fertility,
                    genes.resilience,
                    genes.adaptability,
                    100 - genes.aggression, // Inverze
                    (genes.lifespan / 1.2) // Normalizace životnosti (cca 100 = 100%)
                ],
                backgroundColor: 'rgba(255, 179, 0, 0.4)', // Medová výplň
                borderColor: '#3e2723', // Tmavé dřevo linky
                borderWidth: 2,
                pointBackgroundColor: '#3e2723'
            }]
        },
        options: {
            scales: {
                r: {
                    angleLines: { color: 'rgba(0,0,0,0.2)' },
                    grid: { color: 'rgba(0,0,0,0.1)' },
                    pointLabels: {
                        font: { size: 14, family: 'Cormorant Garamond' },
                        color: '#3e2723'
                    },
                    suggestedMin: 0,
                    suggestedMax: 100,
                    ticks: { display: false } // Skrýt čísla na osách pro čistší vzhled
                }
            },
            plugins: {
                legend: { display: false }
            }
        }
    });
}
function closeMenu() {
    $.post('https://aprts_apiary/close', JSON.stringify({}));
    document.getElementById('app').style.display = 'none';
}

document.onkeyup = function (data) {
    if (data.which == 27) { // ESC
        closeMenu();
    }
};


// --- LOGIKA LEVÉ STRANY ---

function updateLeftPage(maxHives) {
    let list = document.getElementById('hiveList');
    list.innerHTML = "";

    let sortedKeys = Object.keys(currentHivesData).sort((a, b) => Number(a) - Number(b));
    let count = sortedKeys.length;

    sortedKeys.forEach(key => {
        let hive = currentHivesData[key];
        let div = document.createElement('div');
        div.className = 'hive-item';
        if (selectedHiveId == key) div.classList.add('active');

        // Ikona stavu
        let statusIcon = "";
        if (hive.disease) statusIcon = "🦠";
        else if (!hive.hasQueen) statusIcon = "⚠️";
        else if (hive.filledFrames > 0) statusIcon = "🍯";
        else statusIcon = "🐝";

        div.innerHTML = `
            <span><strong>Úl #${key}</strong></span> 
            <span class="hive-status-icon">${statusIcon}</span>
        `;
        div.onclick = () => selectHive(key);
        list.appendChild(div);
    });

    // Update kapacity a tlačítka
    if (maxHives !== null) {
        let btnBuild = document.getElementById('btnBuild');
        let capInfo = document.getElementById('capacityInfo');

        capInfo.innerText = `Kapacita stanoviště: ${count}/${maxHives}`;

        if (count >= maxHives) {
            btnBuild.disabled = true;
            btnBuild.innerHTML = "Stanoviště je plné";
        } else {
            btnBuild.disabled = false;
            btnBuild.innerHTML = '<span class="icon">🔨</span> Založit nový úl';
        }
    }
}

// --- LOGIKA PRAVÉ STRANY (DETAIL) ---

function selectHive(id) {
    selectedHiveId = id;

    // Překreslit levý list (aby se zvýraznil aktivní prvek)
    updateLeftPage(null);

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

    document.getElementById('detailTitle').innerText = `Úl Číslo ${id}`;

    // 1. STATUS STAMP
    let stamp = document.getElementById('statusStamp');
    if (hive.disease) {
        stamp.innerText = "ZAMOŘENO";
        stamp.className = "stamp danger";
    } else if (!hive.hasQueen) {
        stamp.innerText = "BEZ KRÁLOVNY";
        stamp.className = "stamp danger";
    } else if (hive.filledFrames > 0) {
        stamp.innerText = "PRODUKTIVNÍ";
        stamp.className = "stamp ok";
    } else {
        stamp.innerText = "V POŘÁDKU";
        stamp.className = "stamp ok";
    }

    // 2. STATISTIKY
    let queenEl = document.getElementById('lblQueen');
    if (hive.hasQueen) {
        queenEl.innerText = "Aktivní";
        queenEl.className = "stat-value good";
        document.getElementById('lblQueenAge').innerText = `Životnost: ${hive.queenLifespan}`;
    } else {
        queenEl.innerText = "Chybí";
        queenEl.className = "stat-value bad";
        document.getElementById('lblQueenAge').innerText = "---";
    }

    let pop = Math.floor(hive.population);
    document.getElementById('lblPop').innerText = pop.toLocaleString();

    let hp = Math.floor(hive.health);
    document.getElementById('valHealth').innerText = hp + "%";
    document.getElementById('barHealth').style.width = hp + "%";
    document.getElementById('barHealth').style.backgroundColor = hp < 50 ? "#d32f2f" : "#388e3c";

    // 3. VIZUÁLNÍ RÁMKY
    renderVisualFrames(hive);

    // 4. AKTUALIZACE TLAČÍTEK
    let totalInstalled = hive.filledFrames + hive.emptyFrames;

    // Tlačítko: Vložit rám (jen pokud je místo)
    toggleBtn('btnInsertFrame', totalInstalled < hive.maxSlots);

    // Tlačítko: Sklizeň (jen pokud je co brát)
    toggleBtn('btnHarvest', hive.filledFrames > 0);

    // Tlačítko: Lék (jen pokud je nemocný)
    toggleBtn('btnCure', hive.disease != null);

    // --- NOVÁ LOGIKA PRO TLAČÍTKO KRÁLOVNY ---
    let btnQueen = document.getElementById('btnQueen');

    // Reset klonováním (odstraní staré event listenery)
    let newBtn = btnQueen.cloneNode(true);
    btnQueen.parentNode.replaceChild(newBtn, btnQueen);
    btnQueen = newBtn;

    if (hive.hasQueen) {
        // Pokud královna je -> nabídnout vyjmutí
        btnQueen.innerText = "Vyjmout Královnu";
        btnQueen.classList.remove('btn-wood');
        btnQueen.classList.add('btn-red'); // Varovná barva
        btnQueen.disabled = false;

        btnQueen.onclick = function () {
            action('removeQueen');
        };
    } else {
        // Pokud královna není -> nabídnout vložení
        btnQueen.innerText = "Vložit Královnu";
        btnQueen.classList.remove('btn-red');
        btnQueen.classList.add('btn-wood'); // Standardní barva
        btnQueen.disabled = false;

        btnQueen.onclick = function () {
            action('insertQueen');
        };
    }

    // 5. VYKRESLENÍ LOGŮ (NOVÉ)
    renderLogs(hive.logs);
}

function renderVisualFrames(hive) {
    let container = document.getElementById('visualHive');
    container.innerHTML = "";

    let filledCount = hive.filledFrames;
    let emptyCount = hive.emptyFrames;
    let totalInstalled = filledCount + emptyCount;
    let maxSlots = hive.maxSlots;

    for (let i = 0; i < maxSlots; i++) {
        let slot = document.createElement('div');
        slot.className = 'frame-visual';

        // Tooltip text
        let tooltipText = "";

        if (i < filledCount) {
            // PLNÝ
            slot.classList.add('full');
            tooltipText = "Plný rámek medu";
        } else if (i === filledCount && emptyCount > 0) {
            // PRÁVĚ SE PLNÍ
            slot.classList.add('filling');
            slot.style.setProperty('--fill-pct', hive.progress + '%');
            tooltipText = `Plní se: ${hive.progress}%`;
        } else if (i < totalInstalled) {
            // PRÁZDNÝ (VLOŽENÝ)
            slot.classList.add('installed');
            tooltipText = "Prázdný rámek (připraven)";
        } else {
            // PRÁZDNÝ SLOT (NEVLOŽENÝ)
            slot.classList.add('empty-slot');
            tooltipText = "Prázdné místo pro rám";
        }

        slot.title = tooltipText; // Basic HTML tooltip
        container.appendChild(slot);
    }
}

function toggleBtn(id, enable) {
    document.getElementById(id).disabled = !enable;
}

function action(actName) {
    // Pro akce vyžadující vybraný úl
    if (actName !== 'build' && !selectedHiveId) return;

    $.post(`https://aprts_apiary/${actName}`, JSON.stringify({
        apiaryId: currentApiaryId,
        hiveId: selectedHiveId
    }));
}