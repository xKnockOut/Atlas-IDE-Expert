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
    mSnippet: TAtlasSnippet;
    mItem: TAtlasSnippetEntry;
  begin
    for mSnippet in AList do
    begin
      mItem := Default(TAtlasSnippetEntry);
      mItem.Snippet := mSnippet;
      mItem.Snippet.Origin := AOrigin;
      if AOrigin = TAtlasSnippetOrigin.User then
      begin
        mItem.LoadedFile := mSnippet.FileName;
      end;
      FEntries.Add(mItem);
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
  mIndex: Integer;
  mOwn: TAtlasSnippet;
begin
  mOwn := FEntries[AIndex].Snippet;
  Result := False;
  for mIndex := 0 to FEntries.Count - 1 do
  begin
    if (mIndex <> AIndex) and SameText(FEntries[mIndex].Snippet.Prefix, mOwn.Prefix) then
    begin
      // Höherer Vorrang, oder gleiche Herkunft und weiter vorn (die erste gilt).
      if (FEntries[mIndex].Snippet.Origin > mOwn.Origin) or
        ((FEntries[mIndex].Snippet.Origin = mOwn.Origin) and (mIndex < AIndex)) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

function TAtlasSnippetCatalog.UniquePrefix(const ABase: string): string;
var
  mNumber, mIndex: Integer;
  mTaken: Boolean;
begin
  mNumber := 1;
  repeat
    Result := ABase;
    if mNumber > 1 then
    begin
      Result := ABase + IntToStr(mNumber);
    end;
    mTaken := False;
    for mIndex := 0 to FEntries.Count - 1 do
    begin
      if SameText(FEntries[mIndex].Snippet.Prefix, Result) then
      begin
        mTaken := True;
      end;
    end;
    Inc(mNumber);
  until not mTaken;
end;

function TAtlasSnippetCatalog.AddNew: Integer;
var
  mItem: TAtlasSnippetEntry;
begin
  mItem := Default(TAtlasSnippetEntry);
  mItem.Snippet.Prefix := UniquePrefix('neu');
  mItem.Snippet.Name := mItem.Snippet.Prefix;
  mItem.Snippet.Body := '$0';
  mItem.Snippet.Origin := TAtlasSnippetOrigin.User;
  mItem.Changed := True;
  // Eigene stehen vorn; die neue hinter den vorhandenen eigenen.
  Result := 0;
  while (Result < FEntries.Count) and (FEntries[Result].Snippet.Origin = TAtlasSnippetOrigin.User) do
  begin
    Inc(Result);
  end;
  FEntries.Insert(Result, mItem);
  FModified := True;
end;

function TAtlasSnippetCatalog.CopyAsOwn(AIndex: Integer): Integer;
var
  mItem: TAtlasSnippetEntry;
begin
  mItem := Default(TAtlasSnippetEntry);
  mItem.Snippet := FEntries[AIndex].Snippet;
  mItem.Snippet.Origin := TAtlasSnippetOrigin.User;
  mItem.Snippet.FileName := '';
  // Eine Kopie einer eigenen bekäme sonst dasselbe Kürzel zweimal.
  if Editable(AIndex) then
  begin
    mItem.Snippet.Prefix := UniquePrefix(mItem.Snippet.Prefix);
  end;
  mItem.Changed := True;
  Result := 0;
  while (Result < FEntries.Count) and (FEntries[Result].Snippet.Origin = TAtlasSnippetOrigin.User) do
  begin
    Inc(Result);
  end;
  FEntries.Insert(Result, mItem);
  FModified := True;
end;

procedure TAtlasSnippetCatalog.Update(AIndex: Integer; const ASnippet: TAtlasSnippet);
var
  mItem: TAtlasSnippetEntry;
begin
  if not Editable(AIndex) then
  begin
    Exit;
  end;
  mItem := FEntries[AIndex];
  mItem.Snippet.Name := ASnippet.Name;
  mItem.Snippet.Prefix := ASnippet.Prefix;
  mItem.Snippet.Description := ASnippet.Description;
  mItem.Snippet.Body := ASnippet.Body;
  mItem.Changed := True;
  FEntries[AIndex] := mItem;
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
  mBase, mCandidate: string;
  mNumber, mIndex: Integer;
  mTaken: Boolean;
begin
  // Vorhandene Dateien behalten ihren Namen, auch wenn sich das Kürzel ändert.
  if FEntries[AIndex].LoadedFile <> '' then
  begin
    Exit(FEntries[AIndex].LoadedFile);
  end;
  mBase := ChangeFileExt(TAtlasSnippets.FileNameFor(FEntries[AIndex].Snippet.Prefix), '');
  mNumber := 1;
  repeat
    mCandidate := mBase;
    if mNumber > 1 then
    begin
      mCandidate := mBase + '_' + IntToStr(mNumber);
    end;
    Result := TPath.Combine(AFolder, mCandidate + TAtlasSnippets.FileExtension);
    mTaken := FileExists(Result) and (FRemovedFiles.IndexOf(Result) < 0);
    for mIndex := 0 to FEntries.Count - 1 do
    begin
      if (mIndex <> AIndex) and SameText(FEntries[mIndex].LoadedFile, Result) then
      begin
        mTaken := True;
      end;
    end;
    Inc(mNumber);
  until not mTaken;
end;

procedure TAtlasSnippetCatalog.Save(const AFolder: string);
var
  mIndex: Integer;
  mItem: TAtlasSnippetEntry;
  mFileName: string;
begin
  ForceDirectories(AFolder);
  for mFileName in FRemovedFiles do
  begin
    if FileExists(mFileName) then
    begin
      System.SysUtils.DeleteFile(mFileName);
    end;
  end;
  FRemovedFiles.Clear;
  for mIndex := 0 to FEntries.Count - 1 do
  begin
    mItem := FEntries[mIndex];
    if not (Editable(mIndex) and mItem.Changed) then
    begin
      Continue;
    end;
    mFileName := TargetFile(AFolder, mIndex);
    // Atomar (Bericht N3): Ein Abbruch hinterlässt keine halbe Vorlage. UTF-8 mit BOM und CRLF wie bisher.
    TAtlasTextFile.Replace(mFileName, TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(
      StringReplace(TAtlasSnippets.ToFileText(mItem.Snippet), #10, #13#10, [rfReplaceAll])));
    mItem.LoadedFile := mFileName;
    mItem.Snippet.FileName := mFileName;
    mItem.Changed := False;
    FEntries[mIndex] := mItem;
  end;
  FModified := False;
end;

end.
