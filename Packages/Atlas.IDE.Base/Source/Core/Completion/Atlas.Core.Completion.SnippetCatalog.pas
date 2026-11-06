unit Atlas.Core.Completion.SnippetCatalog;

// Datenmodell der Seite „Snippets“ in den Einstellungen (#51, #227): alle
// Code-Vorlagen mit Herkunft, eigene bearbeitbar. Mitgelieferte und IDE-
// Vorlagen sind schreibgeschützt; „Als eigene kopieren“ legt eine eigene mit
// demselben Kürzel an, die sie ersetzt. Speichern schreibt nur geänderte
// eigene Vorlagen als *.atlas-snippet und löscht die Dateien gelöschter.
// Ohne VCL und Open Tools API, damit es sich testen lässt.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Completion.Snippets;

{$SCOPEDENUMS ON}

type
  TAtlasSnippetProblemKind = (PrefixMissing, PrefixInvalid, PrefixTwice, BodyMissing);

  TAtlasSnippetProblem = record
    Index: Integer;
    Kind: TAtlasSnippetProblemKind;
  end;

  TAtlasSnippetEntry = record
    Snippet: TAtlasSnippet;
    /// <summary>Datei, aus der die eigene Vorlage stammt; '' bei neuen.</summary>
    LoadedFile: string;
    Changed: Boolean;
  end;

  TAtlasSnippetCatalog = class
  private
    FEntries: TList<TAtlasSnippetEntry>;
    FRemovedFiles: TList<string>;
    FModified: Boolean;
    function UniquePrefix(const ABase: string): string;
    function TargetFile(const AFolder: string; AIndex: Integer): string;
    /// <summary>Hat eine eigene Vorlage vor AIndex das Kürzel APrefix?</summary>
    function HasEarlierPrefix(AIndex: Integer; const APrefix: string): Boolean;
  public
    /// <summary>Reihenfolge der Liste: eigene, dann IDE, dann mitgelieferte.</summary>
    constructor Create(const ABuiltIn, AIde, AOwn: TAtlasSnippetList);
    destructor Destroy; override;
    function Count: Integer;
    function Entry(AIndex: Integer): TAtlasSnippetEntry;
    function Editable(AIndex: Integer): Boolean;
    /// <summary>Wird die Vorlage von einer mit demselben Kürzel und höherem Vorrang ersetzt?</summary>
    function Replaced(AIndex: Integer): Boolean;
    /// <summary>Neue eigene Vorlage mit freiem Kürzel; liefert ihren Index.</summary>
    function AddNew: Integer;
    /// <summary>Eigene Kopie mit demselben Kürzel (ersetzt das Original); liefert ihren Index.</summary>
    function CopyAsOwn(AIndex: Integer): Integer;
    /// <summary>Nur bei eigenen Vorlagen; Herkunft und Datei bleiben.</summary>
    procedure Update(AIndex: Integer; const ASnippet: TAtlasSnippet);
    /// <summary>Nur bei eigenen Vorlagen.</summary>
    procedure Delete(AIndex: Integer);
    /// <summary>Prüft die eigenen Vorlagen; True ohne Probleme.</summary>
    function Validate(out AProblems: TArray<TAtlasSnippetProblem>): Boolean;
    /// <summary>Schreibt geänderte eigene Vorlagen nach AFolder (UTF-8, CRLF) und löscht die Dateien
    /// gelöschter. Danach gilt nichts mehr als geändert.</summary>
    procedure Save(const AFolder: string);
    property Modified: Boolean read FModified;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  Atlas.Text.Chars,
  Atlas.Core.Files.TextFile;

/// <summary>Besteht das Kürzel nur aus ASCII-Bezeichnerzeichen?</summary>
function IsValidPrefix(const APrefix: string): Boolean;
var
  mPosition: Integer;
begin
  for mPosition := 1 to Length(APrefix) do
  begin
    if not TTextChars.IsAsciiIdentChar(APrefix[mPosition]) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

{ TAtlasSnippetCatalog }

constructor TAtlasSnippetCatalog.Create(const ABuiltIn, AIde, AOwn: TAtlasSnippetList);

  procedure AddAll(const AList: TAtlasSnippetList; AOrigin: TAtlasSnippetOrigin);
  var
    Snippet: TAtlasSnippet;
    Item: TAtlasSnippetEntry;
  begin
    for Snippet in AList do
    begin
      Item := Default(TAtlasSnippetEntry);
      Item.Snippet := Snippet;
      Item.Snippet.Origin := AOrigin;
      if AOrigin = TAtlasSnippetOrigin.User then
      begin
        Item.LoadedFile := Snippet.FileName;
      end;
      FEntries.Add(Item);
    end;
  end;

begin
  inherited Create;
  FEntries := TList<TAtlasSnippetEntry>.Create;
  FRemovedFiles := TList<string>.Create;
  AddAll(AOwn, TAtlasSnippetOrigin.User);
  AddAll(AIde, TAtlasSnippetOrigin.Ide);
  AddAll(ABuiltIn, TAtlasSnippetOrigin.BuiltIn);
end;

destructor TAtlasSnippetCatalog.Destroy;
begin
  FRemovedFiles.Free;
  FEntries.Free;
  inherited;
end;

function TAtlasSnippetCatalog.Count: Integer;
begin
  Result := FEntries.Count;
end;

function TAtlasSnippetCatalog.Entry(AIndex: Integer): TAtlasSnippetEntry;
begin
  Result := FEntries[AIndex];
end;

function TAtlasSnippetCatalog.Editable(AIndex: Integer): Boolean;
begin
  Result := FEntries[AIndex].Snippet.Origin = TAtlasSnippetOrigin.User;
end;

function TAtlasSnippetCatalog.Replaced(AIndex: Integer): Boolean;
var
  Index: Integer;
  Own: TAtlasSnippet;
begin
  Own := FEntries[AIndex].Snippet;
  Result := False;
  for Index := 0 to FEntries.Count - 1 do
  begin
    if (Index <> AIndex) and SameText(FEntries[Index].Snippet.Prefix, Own.Prefix) then
    begin
      // Höherer Vorrang, oder gleiche Herkunft und weiter vorn (die erste gilt).
      if (FEntries[Index].Snippet.Origin > Own.Origin) or
        ((FEntries[Index].Snippet.Origin = Own.Origin) and (Index < AIndex)) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

function TAtlasSnippetCatalog.UniquePrefix(const ABase: string): string;
var
  Number, Index: Integer;
  Taken: Boolean;
begin
  Number := 1;
  repeat
    Result := ABase;
    if Number > 1 then
    begin
      Result := ABase + IntToStr(Number);
    end;
    Taken := False;
    for Index := 0 to FEntries.Count - 1 do
    begin
      if SameText(FEntries[Index].Snippet.Prefix, Result) then
      begin
        Taken := True;
      end;
    end;
    Inc(Number);
  until not Taken;
end;

function TAtlasSnippetCatalog.AddNew: Integer;
var
  Item: TAtlasSnippetEntry;
begin
  Item := Default(TAtlasSnippetEntry);
  Item.Snippet.Prefix := UniquePrefix('neu');
  Item.Snippet.Name := Item.Snippet.Prefix;
  Item.Snippet.Body := '$0';
  Item.Snippet.Origin := TAtlasSnippetOrigin.User;
  Item.Changed := True;
  // Eigene stehen vorn; die neue hinter den vorhandenen eigenen.
  Result := 0;
  while (Result < FEntries.Count) and (FEntries[Result].Snippet.Origin = TAtlasSnippetOrigin.User) do
  begin
    Inc(Result);
  end;
  FEntries.Insert(Result, Item);
  FModified := True;
end;

function TAtlasSnippetCatalog.CopyAsOwn(AIndex: Integer): Integer;
var
  Item: TAtlasSnippetEntry;
begin
  Item := Default(TAtlasSnippetEntry);
  Item.Snippet := FEntries[AIndex].Snippet;
  Item.Snippet.Origin := TAtlasSnippetOrigin.User;
  Item.Snippet.FileName := '';
  // Eine Kopie einer eigenen bekäme sonst dasselbe Kürzel zweimal.
  if Editable(AIndex) then
  begin
    Item.Snippet.Prefix := UniquePrefix(Item.Snippet.Prefix);
  end;
  Item.Changed := True;
  Result := 0;
  while (Result < FEntries.Count) and (FEntries[Result].Snippet.Origin = TAtlasSnippetOrigin.User) do
  begin
    Inc(Result);
  end;
  FEntries.Insert(Result, Item);
  FModified := True;
end;

procedure TAtlasSnippetCatalog.Update(AIndex: Integer; const ASnippet: TAtlasSnippet);
var
  Item: TAtlasSnippetEntry;
begin
  if not Editable(AIndex) then
  begin
    Exit;
  end;
  Item := FEntries[AIndex];
  Item.Snippet.Name := ASnippet.Name;
  Item.Snippet.Prefix := ASnippet.Prefix;
  Item.Snippet.Description := ASnippet.Description;
  Item.Snippet.Body := ASnippet.Body;
  Item.Changed := True;
  FEntries[AIndex] := Item;
  FModified := True;
end;

procedure TAtlasSnippetCatalog.Delete(AIndex: Integer);
begin
  if not Editable(AIndex) then
  begin
    Exit;
  end;
  if FEntries[AIndex].LoadedFile <> '' then
  begin
    FRemovedFiles.Add(FEntries[AIndex].LoadedFile);
  end;
  FEntries.Delete(AIndex);
  FModified := True;
end;

function TAtlasSnippetCatalog.HasEarlierPrefix(AIndex: Integer; const APrefix: string): Boolean;
var
  mOther: Integer;
begin
  for mOther := 0 to AIndex - 1 do
  begin
    if Editable(mOther) and SameText(FEntries[mOther].Snippet.Prefix, APrefix) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasSnippetCatalog.Validate(out AProblems: TArray<TAtlasSnippetProblem>): Boolean;
var
  mIndex: Integer;
  mSnippet: TAtlasSnippet;
  mProblems: TArray<TAtlasSnippetProblem>;

  procedure Add(AKind: TAtlasSnippetProblemKind);
  var
    mProblem: TAtlasSnippetProblem;
  begin
    mProblem.Index := mIndex;
    mProblem.Kind := AKind;
    mProblems := mProblems + [mProblem];
  end;

begin
  mProblems := nil;
  for mIndex := 0 to FEntries.Count - 1 do
  begin
    if not Editable(mIndex) then
    begin
      Continue;
    end;
    mSnippet := FEntries[mIndex].Snippet;
    if Trim(mSnippet.Prefix) = '' then
    begin
      Add(TAtlasSnippetProblemKind.PrefixMissing);
    end
    else
    begin
      if not IsValidPrefix(mSnippet.Prefix) then
      begin
        Add(TAtlasSnippetProblemKind.PrefixInvalid);
      end;
      // Zwei eigene mit demselben Kürzel: einmal melden, bei der zweiten.
      if HasEarlierPrefix(mIndex, mSnippet.Prefix) then
      begin
        Add(TAtlasSnippetProblemKind.PrefixTwice);
      end;
    end;
    if Trim(mSnippet.Body) = '' then
    begin
      Add(TAtlasSnippetProblemKind.BodyMissing);
    end;
  end;
  AProblems := mProblems;
  Result := Length(AProblems) = 0;
end;

function TAtlasSnippetCatalog.TargetFile(const AFolder: string; AIndex: Integer): string;
var
  Base, Candidate: string;
  Number, Index: Integer;
  Taken: Boolean;
begin
  // Vorhandene Dateien behalten ihren Namen, auch wenn sich das Kürzel ändert.
  if FEntries[AIndex].LoadedFile <> '' then
  begin
    Exit(FEntries[AIndex].LoadedFile);
  end;
  Base := ChangeFileExt(TAtlasSnippets.FileNameFor(FEntries[AIndex].Snippet.Prefix), '');
  Number := 1;
  repeat
    Candidate := Base;
    if Number > 1 then
    begin
      Candidate := Base + '_' + IntToStr(Number);
    end;
    Result := TPath.Combine(AFolder, Candidate + TAtlasSnippets.FileExtension);
    Taken := FileExists(Result) and (FRemovedFiles.IndexOf(Result) < 0);
    for Index := 0 to FEntries.Count - 1 do
    begin
      if (Index <> AIndex) and SameText(FEntries[Index].LoadedFile, Result) then
      begin
        Taken := True;
      end;
    end;
    Inc(Number);
  until not Taken;
end;

procedure TAtlasSnippetCatalog.Save(const AFolder: string);
var
  Index: Integer;
  Item: TAtlasSnippetEntry;
  FileName: string;
begin
  ForceDirectories(AFolder);
  for FileName in FRemovedFiles do
  begin
    if FileExists(FileName) then
    begin
      System.SysUtils.DeleteFile(FileName);
    end;
  end;
  FRemovedFiles.Clear;
  for Index := 0 to FEntries.Count - 1 do
  begin
    Item := FEntries[Index];
    if not (Editable(Index) and Item.Changed) then
    begin
      Continue;
    end;
    FileName := TargetFile(AFolder, Index);
    // Atomar (Bericht N3): Ein Abbruch hinterlässt keine halbe Vorlage. UTF-8 mit BOM und CRLF wie bisher.
    TAtlasTextFile.Replace(FileName, TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(
      StringReplace(TAtlasSnippets.ToFileText(Item.Snippet), #10, #13#10, [rfReplaceAll])));
    Item.LoadedFile := FileName;
    Item.Snippet.FileName := FileName;
    Item.Changed := False;
    FEntries[Index] := Item;
  end;
  FModified := False;
end;

end.
