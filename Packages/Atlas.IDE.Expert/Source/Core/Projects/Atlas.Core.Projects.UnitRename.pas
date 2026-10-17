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
    Result := ChangeFileExt(ExtractFileName(AFileName), '');
end;

class function TAtlasUnitRename.IsUnitRename(const AOldFile, ANewFile: string): Boolean;
var
  OldName, NewName: string;
begin
  OldName := UnitNameOf(AOldFile);
  NewName := UnitNameOf(ANewFile);
  Result := (OldName <> '') and (NewName <> '') and not SameText(OldName, NewName);
end;

class function TAtlasUnitRename.SourceFiles(const AFiles: TArray<string>): TArray<string>;
var
  FileName, Known: string;
  Seen: Boolean;
begin
  Result := nil;
  for FileName in AFiles do
  begin
    if (FileName = '') or not MatchText(ExtractFileExt(FileName), ['.pas', '.dpr', '.dpk', '.inc']) then
      Continue;
    Seen := False;
    for Known in Result do
      if SameText(Known, FileName) then
        Seen := True;
    if not Seen then
      Result := Result + [FileName];
  end;
end;

class function TAtlasUnitRename.Arguments(const AOldFile, ANewFile: string; const AFiles: TArray<string>): string;
var
  List, Files: TJSONArray;
  FileName: string;
begin
  List := TJSONArray.Create;
  try
    List.Add(TLspSession.PathToUri(AOldFile));
    List.Add(TLspSession.PathToUri(ANewFile));
    Files := TJSONArray.Create;
    List.AddElement(Files);
    for FileName in SourceFiles(AFiles) do
      Files.Add(TLspSession.PathToUri(FileName));
    Result := List.ToJSON;
  finally
    List.Free;
  end;
end;

class function TAtlasUnitRename.ReadAnswer(AValue: TJSONValue): TAtlasUnitRenameAnswer;
var
  Reply, Edit, Document, Identifier: TJSONObject;
  Item: TJSONValue;
begin
  Result := Default(TAtlasUnitRenameAnswer);
  if not (AValue is TJSONObject) then
    Exit;
  Reply := TJSONObject(AValue);
  if not (Reply.GetValue('enabled') is TJSONBool) or not TJSONBool(Reply.GetValue('enabled')).AsBoolean then
    Exit;
  Result.Enabled := True;
  if Reply.GetValue('old') is TJSONString then
    Result.OldName := Reply.GetValue('old').Value;
  if Reply.GetValue('new') is TJSONString then
    Result.NewName := Reply.GetValue('new').Value;
  if not (Reply.GetValue('edit') is TJSONObject) then
    Exit;
  Edit := TJSONObject(Reply.GetValue('edit'));
  if not (Edit.GetValue('documentChanges') is TJSONArray) then
    Exit;
  for Item in TJSONArray(Edit.GetValue('documentChanges')) do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Document := TJSONObject(Item);
    if not (Document.GetValue('textDocument') is TJSONObject) then
      Continue;
    Identifier := TJSONObject(Document.GetValue('textDocument'));
    if Identifier.GetValue('uri') is TJSONString then
      Result.Files := Result.Files + [TLspSession.UriToPath(Identifier.GetValue('uri').Value)];
  end;
end;

class function TAtlasUnitRename.CountIn(const AAnswer: TAtlasUnitRenameAnswer;
  const AScopeFiles: TArray<string>): Integer;
var
  FileName, Scope: string;
begin
  Result := 0;
  for FileName in AAnswer.Files do
    for Scope in AScopeFiles do
      if SameText(FileName, Scope) then
      begin
        Inc(Result);
        Break;
      end;
end;

{ TAtlasUnitRenameQueue }

function TAtlasUnitRenameQueue.Add(const AEvent: TAtlasUnitRenameEvent): Boolean;
var
  Item: TAtlasUnitRenameEvent;
begin
  Result := False;
  if not TAtlasUnitRename.IsUnitRename(AEvent.OldFile, AEvent.NewFile) then
    Exit;
  for Item in FItems do
    if SameText(Item.OldFile, AEvent.OldFile) and SameText(Item.NewFile, AEvent.NewFile) then
      Exit;
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
