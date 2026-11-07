unit Atlas.Core.Projects.UnitRename;

// uses nachziehen nach dem Umbenennen einer Unit (#512), Plugin-Kern ohne VCL
// und Open Tools API:
// - Ob ein gemeldetes Umbenennen eine Unit betrifft (.pas, anderer Name).
// - Warteschlange: Liegt die Unit in mehreren Projekten der Gruppe, meldet
//   jedes Projekt dasselbe Umbenennen; nachgefragt wird einmal.
// - Dateien eines Bereichs (Projekt oder Projektgruppe) ohne Doppelte, nur
//   Quelltexte (.pas, .dpr, .dpk, .inc).
// - Argumente für atlas.server.unitRenamed und das Lesen der Antwort
//   ({"enabled", "old", "new", "count", "edit"}); betroffene Dateien eines
//   Bereichs zählen, damit der Hinweis beide Zahlen nennen kann.

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  TAtlasUnitRenameScope = (Project, Group);
{$SCOPEDENUMS OFF}

  /// <summary>Gemeldetes Umbenennen einer Unit in einem Projekt.</summary>
  TAtlasUnitRenameEvent = record
    OldFile: string;
    NewFile: string;
    ProjectFile: string;
    class function Create(const AOldFile, ANewFile, AProjectFile: string): TAtlasUnitRenameEvent; static;
  end;

  /// <summary>Antwort des Servers auf atlas.server.unitRenamed.</summary>
  TAtlasUnitRenameAnswer = record
    /// <summary>False: refactoring.unitRenameFollowUp ist "off" (oder keine gültige Antwort).</summary>
    Enabled: Boolean;
    OldName: string;
    NewName: string;
    /// <summary>Dateien, die noch den alten Namen verwenden (Pfade, Reihenfolge des Servers).</summary>
    Files: TArray<string>;
  end;

  TAtlasUnitRename = class
  public const
    Command = 'atlas.server.unitRenamed';
  public
    /// <summary>Betrifft das Umbenennen eine Unit (.pas vorher und nachher, anderer Name)?</summary>
    class function IsUnitRename(const AOldFile, ANewFile: string): Boolean; static;
    /// <summary>Unit-Name zu einer .pas-Datei; '' für andere.</summary>
    class function UnitNameOf(const AFileName: string): string; static;
    /// <summary>Quelltexte aus AFiles ohne Doppelte (Groß-/Kleinschreibung egal), Reihenfolge bleibt.</summary>
    class function SourceFiles(const AFiles: TArray<string>): TArray<string>; static;
    /// <summary>JSON-Argumente [alte URI, neue URI, [URIs]] für atlas.server.unitRenamed.</summary>
    class function Arguments(const AOldFile, ANewFile: string; const AFiles: TArray<string>): string; static;
    /// <summary>Liest die Antwort; ohne gültige Antwort Enabled = False.</summary>
    class function ReadAnswer(AValue: TJSONValue): TAtlasUnitRenameAnswer; static;
    /// <summary>Wie viele der betroffenen Dateien in AScopeFiles liegen.</summary>
    class function CountIn(const AAnswer: TAtlasUnitRenameAnswer; const AScopeFiles: TArray<string>): Integer;
      static;
  end;

  /// <summary>Wartende Umbenennungen; dieselbe (alte und neue Datei) nur einmal.</summary>
  TAtlasUnitRenameQueue = class
  private
    FItems: TArray<TAtlasUnitRenameEvent>;
  public
    /// <summary>False, wenn dieses Umbenennen schon wartet oder keine Unit betrifft.</summary>
    function Add(const AEvent: TAtlasUnitRenameEvent): Boolean;
    /// <summary>Alle wartenden in der Reihenfolge der Meldung; die Schlange ist danach leer.</summary>
    function Take: TArray<TAtlasUnitRenameEvent>;
    function Count: Integer;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Core.Lsp.Session;

{ TAtlasUnitRenameEvent }

class function TAtlasUnitRenameEvent.Create(const AOldFile, ANewFile, AProjectFile: string): TAtlasUnitRenameEvent;
begin
  Result.OldFile := AOldFile;
  Result.NewFile := ANewFile;
  Result.ProjectFile := AProjectFile;
end;

{ TAtlasUnitRename }

class function TAtlasUnitRename.UnitNameOf(const AFileName: string): string;
begin
  Result := '';
  if SameText(ExtractFileExt(AFileName), '.pas') then
  begin
    Result := ChangeFileExt(ExtractFileName(AFileName), '');
  end;
end;

class function TAtlasUnitRename.IsUnitRename(const AOldFile, ANewFile: string): Boolean;
var
  mOldName, mNewName: string;
begin
  mOldName := UnitNameOf(AOldFile);
  mNewName := UnitNameOf(ANewFile);
  Result := (mOldName <> '') and (mNewName <> '') and not SameText(mOldName, mNewName);
end;

class function TAtlasUnitRename.SourceFiles(const AFiles: TArray<string>): TArray<string>;
var
  mFileName, mKnown: string;
  mSeen: Boolean;
begin
  Result := nil;
  for mFileName in AFiles do
  begin
    if (mFileName = '') or not MatchText(ExtractFileExt(mFileName), ['.pas', '.dpr', '.dpk', '.inc']) then
    begin
      Continue;
    end;
    mSeen := False;
    for mKnown in Result do
    begin
      if SameText(mKnown, mFileName) then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      Result := Result + [mFileName];
    end;
  end;
end;

class function TAtlasUnitRename.Arguments(const AOldFile, ANewFile: string; const AFiles: TArray<string>): string;
var
  mList, mFiles: TJSONArray;
  mFileName: string;
begin
  mList := TJSONArray.Create;
  try
    mList.Add(TLspSession.PathToUri(AOldFile));
    mList.Add(TLspSession.PathToUri(ANewFile));
    mFiles := TJSONArray.Create;
    mList.AddElement(mFiles);
    for mFileName in SourceFiles(AFiles) do
    begin
      mFiles.Add(TLspSession.PathToUri(mFileName));
    end;
    Result := mList.ToJSON;
  finally
    mList.Free;
  end;
end;

class function TAtlasUnitRename.ReadAnswer(AValue: TJSONValue): TAtlasUnitRenameAnswer;
var
  mReply, mEdit, mDocument, mIdentifier: TJSONObject;
  mItem: TJSONValue;
begin
  Result := Default(TAtlasUnitRenameAnswer);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mReply := TJSONObject(AValue);
  if not (mReply.GetValue('enabled') is TJSONBool) or not TJSONBool(mReply.GetValue('enabled')).AsBoolean then
  begin
    Exit;
  end;
  Result.Enabled := True;
  if mReply.GetValue('old') is TJSONString then
  begin
    Result.OldName := mReply.GetValue('old').Value;
  end;
  if mReply.GetValue('new') is TJSONString then
  begin
    Result.NewName := mReply.GetValue('new').Value;
  end;
  if not (mReply.GetValue('edit') is TJSONObject) then
  begin
    Exit;
  end;
  mEdit := TJSONObject(mReply.GetValue('edit'));
  if not (mEdit.GetValue('documentChanges') is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mEdit.GetValue('documentChanges')) do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mDocument := TJSONObject(mItem);
    if not (mDocument.GetValue('textDocument') is TJSONObject) then
    begin
      Continue;
    end;
    mIdentifier := TJSONObject(mDocument.GetValue('textDocument'));
    if mIdentifier.GetValue('uri') is TJSONString then
    begin
      Result.Files := Result.Files + [TLspSession.UriToPath(mIdentifier.GetValue('uri').Value)];
    end;
  end;
end;

class function TAtlasUnitRename.CountIn(const AAnswer: TAtlasUnitRenameAnswer;
  const AScopeFiles: TArray<string>): Integer;
var
  mFileName, mScope: string;
begin
  Result := 0;
  for mFileName in AAnswer.Files do
  begin
    for mScope in AScopeFiles do
    begin
      if SameText(mFileName, mScope) then
      begin
        Inc(Result);
        Break;
      end;
    end;
  end;
end;

{ TAtlasUnitRenameQueue }

function TAtlasUnitRenameQueue.Add(const AEvent: TAtlasUnitRenameEvent): Boolean;
var
  mItem: TAtlasUnitRenameEvent;
begin
  Result := False;
  if not TAtlasUnitRename.IsUnitRename(AEvent.OldFile, AEvent.NewFile) then
  begin
    Exit;
  end;
  for mItem in FItems do
  begin
    if SameText(mItem.OldFile, AEvent.OldFile) and SameText(mItem.NewFile, AEvent.NewFile) then
    begin
      Exit;
    end;
  end;
  FItems := FItems + [AEvent];
  Result := True;
end;

function TAtlasUnitRenameQueue.Take: TArray<TAtlasUnitRenameEvent>;
begin
  Result := FItems;
  FItems := nil;
end;

function TAtlasUnitRenameQueue.Count: Integer;
begin
  Result := Length(FItems);
end;

end.
