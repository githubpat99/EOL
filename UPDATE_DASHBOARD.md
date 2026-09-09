# Dashboard aktualisieren

Die Daten bleiben nach Fachbereich getrennt:

- `dashboard_finance_data.json`: Budget, SAP-Ist, Kunden, SN, ZP und separater ITS-Vertrag
- `demografie_powerapps.json`: Demografie- und FTE-Planung
- `EoL_SVZ_V0.6.xlsx`: historische Root-Datei; bleibt als Referenz in OneDrive und wird nicht importiert

Das Dashboard lädt beide Dateien und führt sie nur für die Anzeige zusammen. Dadurch können Finanzen und Demografie unabhängig aktualisiert und versioniert werden.

## Finanzupdate

1. `SN_Kostensicht.xlsm` und `ZP_Kostensicht.xlsm` im Ordner `EOL\Prognose` aktualisieren.
2. Im Dashboard-Verzeichnis auf `Finanzupdate starten.cmd` doppelklicken.
3. Zuerst `SN_Kostensicht.xlsm`, danach `ZP_Kostensicht.xlsm` auswählen.
4. Die Erfolgsmeldung abwarten.

Alternativ kann das Update weiterhin direkt in PowerShell ausgeführt werden:

   ```powershell
   .\scripts\update-dashboard-finance.ps1
   ```

5. Das Skript übernimmt die SAP-Ist-Kosten aus dem Blatt `Kostensicht`, liest «Importierte Perioden» aus der ZP-Kostensicht und vergleicht diesen Stand mit den Monatsübersichten von SN und ZP. Nur identische, lückenlose Perioden werden übernommen. Danach aktualisiert es die SAP-Periodenbeschriftung und verteilt die Plan-Vollkosten anhand der aktuellen Kundenanteile.
6. Budget- und Jahresplanwerte werden direkt in `dashboard_finance_data.json` gepflegt, bis auch dafür eine verbindliche Exportdatei vorliegt.
7. Dashboard prüfen, committen und pushen.

## Demografieupdate

1. Die SVZ-Teamleiter aktualisieren die Demografie in der [Power App](https://make.powerapps.com/e/b6a920fb-95c1-ed80-b27b-b59fcf76d44e/canvas/?action=edit&app-id=%2Fproviders%2FMicrosoft.PowerApps%2Fapps%2F10fd4456-19f9-4014-9b55-73cf4892c56c). Der Zugriff ist nur für die Teamleiter SVZ vorgesehen.
2. Nach Abschluss erhält der Admin die Meldung **ready for update**.
3. Der Admin startet den [Power-Automate-Flow](https://make.powerautomate.com/environments/b6a920fb-95c1-ed80-b27b-b59fcf76d44e/flows/9a72a569-322a-46cc-9fb8-38259ed32c07).
4. Nach erfolgreichem Flow kontrollieren, dass `demografie_powerapps.json` aktualisiert wurde und im Dashboard der neue Stand erscheint.
5. Stichprobenartig Mitarbeiterzahl und FTE-Summen im Reiter «Demografie» prüfen.
6. Die Root-Datei `EoL_SVZ_V0.6.xlsx` nicht als operative Quelle einlesen; sie dient ausschliesslich der historischen Nachvollziehbarkeit.

## Fachliche Kontrollen vor der Veröffentlichung

- ITS steht separat und ist weder im ZP-Steuerertrag noch im Steuer-Total enthalten.
- SN- und ZP-Kundensummen entsprechen den jeweiligen Produkttotalen.
- Die Ist-Aufwände entsprechen der ausgewiesenen SAP-Periode.
- Planaufwände entsprechen den Jahres-Vollkosten.
- Negative Margen bleiben sichtbar und werden nicht auf null gesetzt.
- Datenstand, SAP-Periode und Extraktionsdatum sind plausibel.

## Datenstände

- `dashboard_updated`: Zeitpunkt der letzten Zusammenführung
- `budget_label`: verwendete Budgetversion
- `sap_period`: enthaltene SAP-Buchungsperioden
- `sap_extract_date`: Datum des SAP-Abzugs beziehungsweise der Kostensicht
- Demografie: Stand der separat geladenen Demografiedatei

Der technische Extraktionstag und die fachlich enthaltene Buchungsperiode dürfen nicht gleichgesetzt werden. Ein SAP-Abzug vom September kann weiterhin ausschliesslich die Perioden Januar bis August enthalten.
