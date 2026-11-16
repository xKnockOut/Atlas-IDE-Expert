unit Atlas.UI.Debug.DataBreakpoints.Strings;

// Texte der Datenhaltepunkte: Anhalten, wenn sich ein Feld ändert, und Haltepunkte je Objekt, auf Deutsch und
// Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasDataBreakpointsTextId = (
    DataCommand, DataCommandFor, DataOff, DataNotStopped, DataNoExpression, DataNoSlot, DataNoAddress, DataNoSize,
    DataPartialQuestion, DataRejected, DataSet, DataTextHint, DataSessionHint, DataReassigned, DataChanged, DataStatus,
    DataRemoved, InstanceOff, InstanceNotStopped, InstanceNoBreakpoint, InstanceNoSelf, InstanceNoAddress,
    InstanceNoFields, InstanceRestricted, InstanceFieldSet, InstanceFieldTitle, InstanceFieldSummary,
    InstanceFieldApply, InstanceCancel, InstanceOrphanTitle, InstanceOrphanSummary, InstanceOrphanRemove,
    InstanceOrphanReplace, InstanceOrphanKeep, InstanceOrphanDone);

  TAtlasDataBreakpointsStrings = class
  public
    class function Text(AId: TAtlasDataBreakpointsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasDataBreakpointsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasDataBreakpointsTextId] of string = (
    ('Anhalten, wenn sich das Feld ändert',
     'Anhalten, wenn sich %s ändert',
     'Anhalten, wenn sich ein Feld ändert, ist aus (debug.dataBreakpoints).',
     'Anhalten, wenn sich ein Feld ändert: Das Programm ist nicht angehalten.',
     'Anhalten, wenn sich ein Feld ändert: Unter der Schreibmarke steht kein Feld und keine Variable.',
     'Anhalten, wenn sich ein Feld ändert: Alle %d Plätze für Datenhaltepunkte sind belegt (Debugregister). ' +
       'Bitte erst einen Datenhaltepunkt in der Haltepunktliste entfernen oder ausschalten.',
     'Anhalten, wenn sich ein Feld ändert: Die Adresse von %s ließ sich nicht ermitteln (%s). Eigenschaften und ' +
       'Funktionen haben keine Adresse.',
     'Anhalten, wenn sich ein Feld ändert: Die Größe von %s ließ sich nicht ermitteln (%s).',
     '%s ist %d Byte groß, ein Datenhaltepunkt überwacht höchstens %2:d Byte. Nur die ersten %2:d Byte überwachen?',
     'Anhalten, wenn sich ein Feld ändert: Die IDE hat den Datenhaltepunkt für %s nicht angelegt (alle %d Plätze ' +
       'belegt oder vom Debugger nicht unterstützt).',
     'Anhalten, wenn sich %s ändert: %d Byte an %s überwacht, Wert jetzt %s.',
     'Bei Strings überwacht der Datenhaltepunkt den Zeiger: Er hält bei einer neuen Zuweisung, nicht beim Ändern ' +
       'einzelner Zeichen.',
     'Der Datenhaltepunkt gilt nur für dieses eine Objekt. Atlas entfernt ihn am Ende der Sitzung, weil die ' +
       'Adresse beim nächsten Lauf nicht mehr stimmt.',
     '(neu zugewiesen)',
     'Datenhaltepunkt: %s geändert: %s → %s',
     '%s: %s → %s',
     'Datenhaltepunkte: %d am Ende der Sitzung entfernt.',
     'Haltepunkt nur für ein Objekt ist aus (debug.instanceBreakpoints).',
     'Haltepunkt nur für ein Objekt: Das Programm ist nicht angehalten.',
     'Haltepunkt nur für ein Objekt: In Zeile %d steht kein Haltepunkt.',
     'Haltepunkt nur für ein Objekt: Die Routine in Zeile %d ist keine Methode (kein Self).',
     'Haltepunkt nur für ein Objekt: Die Adresse von Self ließ sich nicht ermitteln (%s).',
     'Haltepunkt nur wenn: Self hat keine Felder mit einfachem Wert.',
     'Haltepunkt %s:%d hält nur noch für %s.',
     'Haltepunkt %s:%d hält nur noch, wenn %s.',
     'Haltepunkt nur wenn …',
     'Bedingung für %s:%d aus einem Feld von Self (aktueller Wert):',
     'Übernehmen',
     'Abbrechen',
     'Haltepunkte für Objekte der letzten Sitzung',
     '%d Haltepunkte sind auf ein Objekt der letzten Sitzung beschränkt; die Adresse gilt nicht mehr.',
     'Adressbedingung entfernen',
     'Durch Feldbedingung ersetzen …',
     'Behalten',
     'Haltepunkt nur für ein Objekt: %d Adressbedingungen entfernt, %d durch Feldbedingungen ersetzt.'),
    ('Break when the field changes',
     'Break when %s changes',
     'Break when a field changes is off (debug.dataBreakpoints).',
     'Break when a field changes: the program is not paused.',
     'Break when a field changes: there is no field or variable under the caret.',
     'Break when a field changes: all %d data breakpoint slots are in use (debug registers). ' +
       'Remove or disable a data breakpoint in the breakpoint list first.',
     'Break when a field changes: could not get the address of %s (%s). Properties and functions have no address.',
     'Break when a field changes: could not get the size of %s (%s).',
     '%s is %d bytes, a data breakpoint watches at most %2:d bytes. Watch only the first %2:d bytes?',
     'Break when a field changes: the IDE did not create the data breakpoint for %s (all %d slots in use or not ' +
       'supported by the debugger).',
     'Break when %s changes: watching %d bytes at %s, value now %s.',
     'For strings the data breakpoint watches the pointer: it stops on a new assignment, not when single ' +
       'characters change.',
     'The data breakpoint applies to this one object only. Atlas removes it when the session ends because the ' +
       'address will be different on the next run.',
     '(reassigned)',
     'Data breakpoint: %s changed: %s → %s',
     '%s: %s → %s',
     'Data breakpoints: %d removed at the end of the session.',
     'Breakpoint only for one object is off (debug.instanceBreakpoints).',
     'Breakpoint only for one object: the program is not paused.',
     'Breakpoint only for one object: there is no breakpoint on line %d.',
     'Breakpoint only for one object: the routine on line %d is not a method (no Self).',
     'Breakpoint only for one object: the address of Self could not be determined (%s).',
     'Breakpoint only if: Self has no fields with a simple value.',
     'Breakpoint %s:%d now only stops for %s.',
     'Breakpoint %s:%d now only stops if %s.',
     'Breakpoint only if …',
     'Condition for %s:%d from a field of Self (current value):',
     'Apply',
     'Cancel',
     'Breakpoints for objects of the last session',
     '%d breakpoints are restricted to an object of the last session; the address is no longer valid.',
     'Remove address condition',
     'Replace with field condition …',
     'Keep',
     'Breakpoint only for one object: %d address conditions removed, %d replaced with field conditions.'));

{ TAtlasDataBreakpointsStrings }

class function TAtlasDataBreakpointsStrings.Text(AId: TAtlasDataBreakpointsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasDataBreakpointsStrings.Fmt(AId: TAtlasDataBreakpointsTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
