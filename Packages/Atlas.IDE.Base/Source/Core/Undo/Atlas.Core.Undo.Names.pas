unit Atlas.Core.Undo.Names;

// Texte der Einstellungen undo.multiFile.onConflict und undo.multiFile.newFiles
// (#721) und ihre Aufzählungswerte. Steht im Root des Features Undo, weil ein
// Contract nur Typen und Interfaces enthält (Code-Review A-10, Konzept 7.1).

interface

uses
  Atlas.Core.Undo.Contract;

type
  TAtlasUndoNames = class
  public
    /// <summary>"partial" oder "abort".</summary>
    class function ConflictModeName(AMode: TAtlasUndoConflictMode): string; static;
    /// <summary>Unbekannter Text liefert Partial.</summary>
    class function ParseConflictMode(const AText: string): TAtlasUndoConflictMode; static;
    /// <summary>"recycleBin", "delete" oder "keep".</summary>
    class function NewFilesName(AMode: TAtlasNewFilesMode): string; static;
    /// <summary>Unbekannter Text liefert RecycleBin.</summary>
    class function ParseNewFiles(const AText: string): TAtlasNewFilesMode; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasUndoNames }

class function TAtlasUndoNames.ConflictModeName(AMode: TAtlasUndoConflictMode): string;
begin
  if AMode = TAtlasUndoConflictMode.Abort then
    Result := 'abort'
  else
    Result := 'partial';
end;

class function TAtlasUndoNames.ParseConflictMode(const AText: string): TAtlasUndoConflictMode;
begin
  if SameText(Trim(AText), 'abort') then
    Result := TAtlasUndoConflictMode.Abort
  else
    Result := TAtlasUndoConflictMode.Partial;
end;

class function TAtlasUndoNames.NewFilesName(AMode: TAtlasNewFilesMode): string;
begin
  case AMode of
    TAtlasNewFilesMode.Delete:
      Result := 'delete';
    TAtlasNewFilesMode.Keep:
      Result := 'keep';
  else
    Result := 'recycleBin';
  end;
end;

class function TAtlasUndoNames.ParseNewFiles(const AText: string): TAtlasNewFilesMode;
begin
  if SameText(Trim(AText), 'delete') then
    Result := TAtlasNewFilesMode.Delete
  else if SameText(Trim(AText), 'keep') then
    Result := TAtlasNewFilesMode.Keep
  else
    Result := TAtlasNewFilesMode.RecycleBin;
end;

end.
