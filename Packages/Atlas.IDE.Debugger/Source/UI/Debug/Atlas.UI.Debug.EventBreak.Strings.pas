unit Atlas.UI.Debug.EventBreak.Strings;

// Texte von „Beim nächsten Ereignis anhalten“, auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base
// (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasEventBreakTextId = (
    EventBreakTitle, EventBreakCategories, EventBreakMouse, EventBreakKeyboard, EventBreakTimer, EventBreakWindow,
    EventBreakDatabase, EventBreakActions, EventBreakOther, EventBreakFrequent, EventBreakScope, EventBreakAllForms,
    EventBreakVisibleForms, EventBreakOneForm, EventBreakOk, EventBreakCancel, EventBreakCount, EventBreakNoProcess,
    EventBreakOff, EventBreakNoHandlers, EventBreakFailed, EventBreakMany, EventBreakWatching, EventBreakUnresolved,
    EventBreakStopped, EventBreakElsewhere, EventBreakEnded, EventBreakCancelled, EventBreakContinue, EventBreakClose,
    EventBreakVisibleUnknown);

  TAtlasEventBreakStrings = class
  public
    class function Text(AId: TAtlasEventBreakTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasEventBreakTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasEventBreakTextId] of string = (
    ('Beim nächsten Ereignis anhalten',
     'Ereignisarten',
     'Maus (OnClick, OnDblClick, OnMouseDown …)',
     'Tastatur (OnKeyDown, OnKeyPress …)',
     'Timer (OnTimer)',
     'Fenster (OnShow, OnActivate, OnResize, OnClose …)',
     'Datenbank (BeforePost, AfterScroll, OnCalcFields …)',
     'Aktionen (OnExecute)',
     'Sonstige',
     'Häufige Ereignisse einschließen (%s, Timer unter 100 ms)',
     'Formulare',
     'Alle Formulare',
     'Nur die gerade sichtbaren Formulare',
     'Nur dieses Formular:',
     'Beobachten',
     'Abbrechen',
     '%d Handler an %d Stellen',
     'Beim nächsten Ereignis anhalten: Es läuft kein Programm im Debugger.',
     'Beim nächsten Ereignis anhalten ist ausgeschaltet (Tools › Optionen › Atlas › Debuggen).',
     'Beim nächsten Ereignis anhalten: Keine Handler für diese Auswahl.',
     'Beim nächsten Ereignis anhalten: %s',
     'Beim nächsten Ereignis anhalten: %d Haltepunkte; das Setzen kann einige Sekunden dauern.',
     'Beim nächsten Ereignis anhalten: %d Haltepunkte gesetzt, warte auf das nächste Ereignis.',
     'Beim nächsten Ereignis anhalten: %d Handler ohne auffindbaren Rumpf bleiben unbeobachtet.',
     'Angehalten: %s',
     'Beim nächsten Ereignis anhalten: Das Programm hielt an einer anderen Stelle (%s:%d); die Beobachtung ist beendet.',
     'Beim nächsten Ereignis anhalten: Das Programm ist beendet; die Haltepunkte sind entfernt.',
     'Beim nächsten Ereignis anhalten: Beobachtung beendet, Haltepunkte entfernt.',
     'Weiter beobachten',
     'Schließen',
     'Beim nächsten Ereignis anhalten: Die sichtbaren Formulare ließen sich nicht ermitteln; beobachtet werden alle.'),
    ('Break on next event',
     'Event kinds',
     'Mouse (OnClick, OnDblClick, OnMouseDown …)',
     'Keyboard (OnKeyDown, OnKeyPress …)',
     'Timer (OnTimer)',
     'Window (OnShow, OnActivate, OnResize, OnClose …)',
     'Database (BeforePost, AfterScroll, OnCalcFields …)',
     'Actions (OnExecute)',
     'Other',
     'Include frequent events (%s, timers below 100 ms)',
     'Forms',
     'All forms',
     'Only the forms visible right now',
     'Only this form:',
     'Watch',
     'Cancel',
     '%d handlers at %d places',
     'Break on next event: no program is running in the debugger.',
     'Break on next event is turned off (Tools › Options › Atlas › Debugging).',
     'Break on next event: no handlers for this choice.',
     'Break on next event: %s',
     'Break on next event: %d breakpoints; setting them can take a few seconds.',
     'Break on next event: %d breakpoints set, waiting for the next event.',
     'Break on next event: %d handlers without a body found stay unwatched.',
     'Stopped: %s',
     'Break on next event: the program stopped elsewhere (%s:%d); watching ended.',
     'Break on next event: the program ended; the breakpoints are removed.',
     'Break on next event: watching ended, breakpoints removed.',
     'Keep watching',
     'Close',
     'Break on next event: the visible forms could not be determined; watching all.'));

{ TAtlasEventBreakStrings }

class function TAtlasEventBreakStrings.Text(AId: TAtlasEventBreakTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasEventBreakStrings.Fmt(AId: TAtlasEventBreakTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
