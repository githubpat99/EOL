# Power Apps Demografie-Planung

## Zielbild

Die CSV/JSON-Dateien bleiben als Migrations- und Exportformat erhalten. Die operative Pflege erfolgt in einer Microsoft Lists-/SharePoint-Liste und einer Canvas-App. Alle Teamleiter duerfen alle Eintraege bearbeiten.

## 1. SharePoint-Liste anlegen

1. In Microsoft Lists **Neue Liste** > **Aus Excel** waehlen.
2. `demografie_powerapps_import.csv` zuerst in Excel oeffnen und bei Bedarf als `.xlsx` speichern.
3. Die Excel-Datei hochladen.
4. Liste **Demografie Planung** nennen.
5. Spaltentypen pruefen:

| Spalte | Typ | Pflicht | Hinweis |
| --- | --- | --- | --- |
| Titel | Einzelne Textzeile | Ja | Technischer eindeutiger Anzeigetext |
| Team | Auswahl | Ja | ABP, EZR, EZV, SNV, SVZ |
| Mitarbeiter | Einzelne Textzeile | Ja | Name der Person |
| Fachgebiet | Einzelne Textzeile | Ja | Fachliche Zuordnung |
| Planjahr | Zahl, 0 Dezimalstellen | Ja | 2026 bis 2036 |
| Pensum | Zahl, 2 Dezimalstellen | Ja | Nur Werte von 0 bis 1 |

Ergaenze in der Liste eine eindeutige Inhaltsregel: Die Kombination aus `Team`, `Mitarbeiter`, `Fachgebiet` und `Planjahr` darf nur einmal vorkommen.

## 2. Canvas-App erstellen

1. In Power Apps **Create** > **Blank canvas app** > **Tablet** waehlen.
2. Unter **Data** die SharePoint-Liste **Demografie Planung** verbinden.
3. Die Datenquelle in den folgenden Formeln als `'Demografie Planung'` verwenden.

### Startbildschirm

- Dropdown `ddTeam`
  - `Items`: `Sort(Distinct('Demografie Planung'; Team); Value)`
- Dropdown `ddMitarbeiter`
  - `Items`: `Sort(Distinct(Filter('Demografie Planung'; IsBlank(ddTeam.Selected.Value) || Team = ddTeam.Selected.Value); Mitarbeiter); Value)`
- Galerie `galPlanung`
  - `Items`:

```powerfx
SortByColumns(
    Filter(
        'Demografie Planung';
        IsBlank(ddTeam.Selected.Value) || Team = ddTeam.Selected.Value;
        IsBlank(ddMitarbeiter.Selected.Value) || Mitarbeiter = ddMitarbeiter.Selected.Value
    );
    "Planjahr";
    SortOrder.Ascending
)
```

Die Galerie zeigt `Mitarbeiter`, `Team`, `Fachgebiet`, `Planjahr` und `Pensum`.

### Pensum direkt speichern

Fuer ein Texteingabefeld `txtPensum` in der Galerie:

- `Default`: `ThisItem.Pensum`
- `OnChange`:

```powerfx
If(
    Value(Self.Text) >= 0 && Value(Self.Text) <= 1;
    Patch(
        'Demografie Planung';
        ThisItem;
        {
            Pensum: Value(Self.Text);
            Titel: ThisItem.Team & " | " & ThisItem.Mitarbeiter & " | " & ThisItem.Fachgebiet & " | " & ThisItem.Planjahr
        }
    );
    Notify("Pensum muss zwischen 0 und 1 liegen."; NotificationType.Error)
)
```

### Neues Fachgebiet

Ein Formular mit Feldern Team, Mitarbeiter, Fachgebiet und Startwert anlegen. Der Button **Fachgebiet anlegen** erstellt fuer alle Jahre die Datensaetze:

```powerfx
ForAll(
    Sequence(11; 2026; 1);
    Patch(
        'Demografie Planung';
        Defaults('Demografie Planung');
        {
            Team: ddNeuesTeam.Selected.Value;
            Mitarbeiter: txtNeuerMitarbeiter.Text;
            Fachgebiet: txtNeuesFachgebiet.Text;
            Planjahr: Value;
            Pensum: 0;
            Titel: ddNeuesTeam.Selected.Value & " | " & txtNeuerMitarbeiter.Text & " | " & txtNeuesFachgebiet.Text & " | " & Value
        }
    )
);
Refresh('Demografie Planung');
Notify("Fachgebiet für 2026 bis 2036 angelegt."; NotificationType.Success)
```

### Fachgebiet loeschen

Vorher `Confirm()` oder einen eigenen Dialog einsetzen. Nach Bestaetigung:

```powerfx
RemoveIf(
    'Demografie Planung';
    Team = galPlanung.Selected.Team &&
    Mitarbeiter = galPlanung.Selected.Mitarbeiter &&
    Fachgebiet = galPlanung.Selected.Fachgebiet
);
Refresh('Demografie Planung')
```

## 3. Berechtigungen und Backup

- Teamleiter als Mitglieder der SharePoint-Site hinzufügen; sie duerfen alle Eintraege bearbeiten.
- Der Versionsverlauf der SharePoint-Liste muss aktiviert bleiben. Er ist das operative Backup und ermoeglicht Wiederherstellungen einzelner Eintraege.
- Vor groesseren Planungsrunden die Liste ueber **Export to Excel** sichern.
- Die bisherige `Backup_2026-08-26.json` unveraendert als Ausgangspunkt aufbewahren.

## 4. JSON fuer das bestehende Dashboard

Die Power-App ersetzt mittelfristig den CSV-Workflow. Solange das GitHub-Dashboard weiter verwendet wird, wird die SharePoint-Liste periodisch nach Excel/CSV exportiert und danach mit dem vorhandenen Konverter in `demografie.json` ueberfuehrt.

Eine vollautomatische Kopplung ist als naechster Schritt mit Power Automate sinnvoll: Bei Aenderung eines Listeneintrags eine JSON-Datei erzeugen und das Dashboard aktualisieren.
