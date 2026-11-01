unit Atlas.Core.Undo.Contract;

// Atlas-Änderungssätze (#721): Eine Atlas-Aktion, die mehr als eine Datei
// ändert (oder Dateien anlegt bzw. löscht), wird als ein Satz protokolliert:
// Aktion, Zeitpunkt und je Datei der Inhalt vorher und nachher samt Kodierung
// und Zeilenenden (#121). Das Ziel (IAtlasUndoTarget) schreibt beim
// Zurücknehmen und Wiederherstellen: in der IDE offene Dateien über ihren
// Puffer, Formulare über den Designer, sonst die Platte. Der Speicher
// (IAtlasUndoStore) sichert die Sätze über einen Neustart hinweg.

interface

uses
  System.SysUtils,
  Atlas.Core.Files.Contract;

type
{$SCOPEDENUMS ON}
  TAtlasFileChangeKind = (Modified, Created, Deleted);
  /// <summary>undo.multiFile.onConflict: nur die Dateien ohne Konflikt zurücknehmen oder gar nichts.</summary>
  TAtlasUndoConflictMode = (Partial, Abort);
  /// <summary>undo.multiFile.newFiles: neu angelegte Dateien beim Zurücknehmen.</summary>
  TAtlasNewFilesMode = (RecycleBin, Delete, Keep);
  TAtlasChangeSetState = (Applied, PartlyUndone, Undone);
  /// <summary>Warum eine Datei nicht zurückgenommen bzw. wiederhergestellt wurde.</summary>
  TAtlasUndoProblemKind = (
    /// <summary>Die betroffenen Stellen wurden nach der Aktion geändert.</summary>
    ChangedSince,
    /// <summary>Die Datei gibt es (wieder), sie soll aber angelegt werden.</summary>
    Exists,
    /// <summary>Die Datei fehlt.</summary>
    Missing,
    /// <summary>Schreiben schlug fehl (Message).</summary>
    Failed);
{$SCOPEDENUMS OFF}

  TAtlasFileChange = record
    FileName: string;
    Kind: TAtlasFileChangeKind;
    /// <summary>Inhalt vor der Aktion; leer bei Created.</summary>
    Before: TAtlasTextFileContent;
    /// <summary>Inhalt nach der Aktion; leer bei Deleted.</summary>
    After: TAtlasTextFileContent;
    /// <summary>Projekt (.dproj), in das die Datei eingetragen ist bzw. war; '' = keins.</summary>
    Project: string;
    /// <summary>Diese Datei ist zurückgenommen.</summary>
    Undone: Boolean;
    class function Modified(const AFileName: string; const ABefore, AAfter: TAtlasTextFileContent):
      TAtlasFileChange; static;
    class function Created(const AFileName, AProject: string; const AContent: TAtlasTextFileContent):
      TAtlasFileChange; static;
    class function Deleted(const AFileName, AProject: string; const AContent: TAtlasTextFileContent):
      TAtlasFileChange; static;
  end;

  TAtlasChangeSet = record
    Id: Integer;
    /// <summary>Was Atlas getan hat, z. B. „Umbenennen: Alt → Neu“.</summary>
    Action: string;
    Time: TDateTime;
    Files: TArray<TAtlasFileChange>;
    function State: TAtlasChangeSetState;
    /// <summary>Ungefähre Größe im Speicher in Byte (Texte vorher und nachher).</summary>
    function Size: Int64;
    /// <summary>Index der Datei oder -1.</summary>
    function IndexOf(const AFileName: string): Integer;
  end;

  TAtlasUndoProblem = record
    FileName: string;
    Kind: TAtlasUndoProblemKind;
    /// <summary>Bei Failed die Fehlermeldung.</summary>
    Message: string;
  end;

  TAtlasUndoReport = record
    SetId: Integer;
    Action: string;
    /// <summary>Wiederherstellen statt Zurücknehmen.</summary>
    Redo: Boolean;
    /// <summary>Kein passender Satz (leeres Protokoll, unbekannte Kennung, schon zurückgenommen).</summary>
    NotFound: Boolean;
    /// <summary>Protokoll ausgeschaltet (undo.multiFile).</summary>
    Disabled: Boolean;
    /// <summary>Wegen Konflikten nichts geändert (undo.multiFile.onConflict = abort).</summary>
    Aborted: Boolean;
    /// <summary>Geänderte Dateien.</summary>
    Done: TArray<string>;
    Conflicts: TArray<TAtlasUndoProblem>;
    Errors: TArray<TAtlasUndoProblem>;
    /// <summary>Etwas geändert und kein Konflikt, kein Fehler.</summary>
    function Complete: Boolean;
  end;

  /// <summary>Schreibt Dateien beim Zurücknehmen und Wiederherstellen.
  /// Ausnahmen gelten als Fehler der Datei.</summary>
  IAtlasUndoTarget = interface
    ['{6B1E4D27-3A95-4C08-9F72-E5D8A13C40B6}']
    /// <summary>Aktueller Inhalt (offener Puffer, Formular im Designer, sonst Platte); False, wenn die Datei
    /// fehlt.</summary>
    function Read(const AFileName: string; out AContent: TAtlasTextFileContent): Boolean;
    /// <summary>Vorhandene Datei ändern; ein offener Puffer als ein Rückgängig-Schritt.</summary>
    procedure Write(const AFileName: string; const AContent: TAtlasTextFileContent);
    /// <summary>Datei anlegen (wiederherstellen) und, wenn AProject gesetzt ist, ins Projekt eintragen.</summary>
    procedure CreateFile(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
    /// <summary>Datei aus AProject austragen, schließen und nach AMode löschen, in den Papierkorb verschieben
    /// oder behalten.</summary>
    procedure RemoveFile(const AFileName, AProject: string; AMode: TAtlasNewFilesMode);
  end;

  /// <summary>Sichert Sätze über einen Neustart hinweg.</summary>
  IAtlasUndoStore = interface
    ['{0F3C7A52-8E41-4B6D-A2C9-71D4E06B5F83}']
    /// <summary>Satz (neu) sichern; ältere Sätze fallen weg, bis die Größenbegrenzung passt.</summary>
    procedure Save(const ASet: TAtlasChangeSet);
    procedure Delete(AId: Integer);
    /// <summary>Alle gesicherten Sätze, älteste zuerst; unlesbare werden übergangen.</summary>
    function Load: TArray<TAtlasChangeSet>;
    procedure Clear;
  end;

  TAtlasUndoFileProc = reference to procedure(const AFileName, AProject: string);

  /// <summary>Haken des Plattenziels: Projekt und Papierkorb kennt nur die IDE-Schicht.</summary>
  TAtlasUndoDiskHooks = record
    OnAddToProject: TAtlasUndoFileProc;
    OnRemoveFromProject: TAtlasUndoFileProc;
    /// <summary>Datei in den Papierkorb verschieben; nil = löschen.</summary>
    OnRecycle: TProc<string>;
  end;

  /// <summary>Legt das Plattenziel an; die Kompositionswurzel setzt den Adapter ein.</summary>
  TAtlasUndoDiskFactory = reference to function(const AHooks: TAtlasUndoDiskHooks): IAtlasUndoTarget;
  /// <summary>Legt die Sicherung im Ordner AFolder an (AMaxBytes = 0: ohne Begrenzung, nur zum Leeren).</summary>
  TAtlasUndoStoreFactory = reference to function(const AFolder: string; AMaxBytes: Int64): IAtlasUndoStore;

implementation

{ TAtlasFileChange }

class function TAtlasFileChange.Modified(const AFileName: string; const ABefore,
  AAfter: TAtlasTextFileContent): TAtlasFileChange;
begin
  Result := Default(TAtlasFileChange);
  Result.FileName := AFileName;
  Result.Kind := TAtlasFileChangeKind.Modified;
  Result.Before := ABefore;
  Result.After := AAfter;
end;

class function TAtlasFileChange.Created(const AFileName, AProject: string;
  const AContent: TAtlasTextFileContent): TAtlasFileChange;
begin
  Result := Default(TAtlasFileChange);
  Result.FileName := AFileName;
  Result.Kind := TAtlasFileChangeKind.Created;
  Result.After := AContent;
  Result.Project := AProject;
end;

class function TAtlasFileChange.Deleted(const AFileName, AProject: string;
  const AContent: TAtlasTextFileContent): TAtlasFileChange;
begin
  Result := Default(TAtlasFileChange);
  Result.FileName := AFileName;
  Result.Kind := TAtlasFileChangeKind.Deleted;
  Result.Before := AContent;
  Result.Project := AProject;
end;

{ TAtlasChangeSet }

function TAtlasChangeSet.State: TAtlasChangeSetState;
var
  Change: TAtlasFileChange;
  Undone: Integer;
begin
  Undone := 0;
  for Change in Files do
    if Change.Undone then
      Inc(Undone);
  if Undone = 0 then
    Result := TAtlasChangeSetState.Applied
  else if Undone = Length(Files) then
    Result := TAtlasChangeSetState.Undone
  else
    Result := TAtlasChangeSetState.PartlyUndone;
end;

function TAtlasChangeSet.Size: Int64;
var
  Change: TAtlasFileChange;
begin
  Result := Length(Action) * SizeOf(Char);
  for Change in Files do
    Inc(Result, Int64(Length(Change.FileName) + Length(Change.Before.Text) + Length(Change.After.Text)) *
      SizeOf(Char));
end;

function TAtlasChangeSet.IndexOf(const AFileName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Files) do
    if SameText(Files[Index].FileName, AFileName) then
      Exit(Index);
  Result := -1;
end;

{ TAtlasUndoReport }

function TAtlasUndoReport.Complete: Boolean;
begin
  Result := (Length(Done) > 0) and (Length(Conflicts) = 0) and (Length(Errors) = 0) and not Aborted;
end;

end.
