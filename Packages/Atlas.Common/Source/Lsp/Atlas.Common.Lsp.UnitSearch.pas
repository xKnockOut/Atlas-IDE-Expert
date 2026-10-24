unit Atlas.Common.Lsp.UnitSearch;

// Daten für das Fenster „Units suchen“ des Plugins (#777):
//   - Befehl atlas.server.units []: alle Units aus Index und Projektmodell mit
//     Datei, Projekten, Herkunft (project, searchPath, library) und Art (form,
//     frame, dm, unit, test, inc). Kein Dateizugriff außer der Frage, ob eine
//     Formulardatei neben der Unit liegt.
//   - Befehl atlas.server.unitPreview [uri, {form, usedBy}]: Vorschau ohne die
//     Unit im Editor zu öffnen: Kopfkommentar, Typen im interface (mit
//     Gesamtzahl typeCount), uses beider Abschnitte, Zeilenzahl, letzte
//     Änderung, Git-Zustand, Formularskizze und „Verwendet von“.
//   - Befehl atlas.server.addUses [uri, [Units], {"section"}]: „In uses
//     aufnehmen“; ohne "section" entscheidet der interface-Teil, mit
//     "interface" bzw. "implementation" gilt der Abschnitt fest („Unit
//     verwenden“, Alt+F11, #786).
// Art: Vorfahrenkette der Klassen im interface bis TForm/TCustomForm, TFrame/
// TCustomFrame oder TDataModule; ohne bekannte Kette, aber mit .dfm/.fmx ein
// Formular. Test: uses DUnitX.TestFramework bzw. TestFramework, oder die Unit
// gehört nur zu Testprojekten.
// Projekte, Index und Dateien liefert TUnitSearchContextProvider (Shell).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Editing.UsesActions;

type
  /// <summary>Ein Projekt der Gruppe mit seinen Dateien.</summary>
  TUnitSearchProject = record
    /// <summary>Name ohne Endung, z. B. Atlas.IDE.Expert.</summary>
    Name: string;
    /// <summary>.dproj; '' ohne Projektdatei.</summary>
    FileName: string;
    /// <summary>Quelltexte des Projekts (Hauptdatei, DCCReference).</summary>
    Files: TArray<string>;
    /// <summary>Hauptprogramm nutzt DUnitX bzw. DUnit.</summary>
    IsTest: Boolean;
  end;

  TUnitSearchContext = record
    Units: TArray<TUnitIndex>;
    Projects: TArray<TUnitSearchProject>;
    /// <summary>Vorfahren eines Typs (Klasse) laut Index; nil wenn unbekannt.</summary>
    AncestorsOf: TFunc<string, TArray<string>>;
    /// <summary>Gibt es die Datei?</summary>
    Exists: TFunc<string, Boolean>;
    /// <summary>Inhalt einer Datei (auch offene Dokumente); '' wenn sie fehlt.</summary>
    ReadText: TFunc<string, string>;
    /// <summary>Letzte Änderung; 0 wenn unbekannt.</summary>
    Modified: TFunc<string, TDateTime>;
    /// <summary>Git-Zustand der Datei (siehe TUnitSearch.GitState); '' ohne Git oder Repository.</summary>
    GitState: TFunc<string, string>;
    /// <summary>uses-Kontext (Declaring, Namespaces) zur URI der Datei, in die „uses aufnehmen“ schreibt.</summary>
    UsesFor: TFunc<string, TUsesContext>;
  end;

  TUnitSearchContextProvider = reference to function(out AContext: TUnitSearchContext): Boolean;

  /// <summary>Komponente der Formularskizze in Pixeln des Formulars, absolut.</summary>
  TUnitSketchItem = record
    Name: string;
    TypeName: string;
    Caption: string;
    Left, Top, Width, Height: Integer;
    /// <summary>Tiefe im Komponentenbaum, 1 = direkt auf dem Formular.</summary>
    Depth: Integer;
  end;

  TUnitSketch = record
    FormClass: string;
    Caption: string;
    Width, Height: Integer;
    Items: TArray<TUnitSketchItem>;
  end;

  TUnitSearch = class
  public const
    UnitsCommand = 'atlas.server.units';
    PreviewCommand = 'atlas.server.unitPreview';
    AddUsesCommand = 'atlas.server.addUses';
    /// <summary>Höchstzahl der Komponenten in der Skizze.</summary>
    MaxSketchItems = 200;
    MaxHeaderLines = 12;
    MaxTypes = 40;
    MaxUsedBy = 12;
  private
    FContextFor: TUnitSearchContextProvider;
  public
    constructor Create(const AContextFor: TUnitSearchContextProvider);
    /// <summary>Art der Unit: form, frame, dm, test oder unit.</summary>
    class function KindOf(const AUnit: TUnitIndex; const AAncestorsOf: TFunc<string, TArray<string>>;
      AHasForm, AOnlyTestProjects: Boolean): string; static;
    /// <summary>Formulardatei neben AFileName (.dfm, dann .fmx); '' ohne.</summary>
    class function FormFileOf(const AFileName: string; const AExists: TFunc<string, Boolean>): string; static;
    /// <summary>Kommentar vor „unit …;“ ohne Kommentarzeichen, höchstens MaxHeaderLines Zeilen.</summary>
    class function HeaderComment(const AText: string): string; static;
    /// <summary>Zeilenzahl des Textes (letzte Zeile ohne Umbruch zählt mit).</summary>
    class function LineCount(const AText: string): Integer; static;
    /// <summary>Zustand aus „git status --porcelain“: clean, modified, added, deleted, renamed, untracked,
    /// conflict; '' ohne Repository (ALines = nil und AInRepo = False).</summary>
    class function GitState(const ALines: TArray<string>; AInRepo: Boolean): string; static;
    /// <summary>Skizze aus der Formulardatei: absolute Lage aus Left/Top samt einfachem Align.</summary>
    class function Sketch(const AFormText: string): TUnitSketch; static;
    /// <summary>Namen der Units, die AUnitName in uses haben (ohne Bibliothek), sortiert.</summary>
    class function UsedBy(const AUnits: TArray<TUnitIndex>; const AUnitName: string): TArray<string>; static;
    /// <summary>Antwort auf atlas.server.units.</summary>
    class function UnitsJson(const AContext: TUnitSearchContext): TJSONObject; static;
    /// <summary>Antwort auf atlas.server.unitPreview; AWithForm/AWithUsedBy schalten die Teile.</summary>
    class function PreviewJson(const AContext: TUnitSearchContext; const AFileName: string;
      AWithForm, AWithUsedBy: Boolean): TJSONObject; static;
    /// <summary>Antwort auf atlas.server.addUses: {edit: WorkspaceEdit oder null, added: [Namen]}.
    /// Jede Unit kommt ins interface-uses, wenn ein Bezeichner des interface-Teils aus ihr stammt,
    /// sonst ins implementation-uses; vorhandene Units entfallen.</summary>
    class function AddUsesJson(const AUri, AText: string; const AUnits: TArray<string>;
      const AUses: TUsesContext): TJSONObject; overload; static;
    /// <summary>Wie oben mit festem Abschnitt ATarget (#786).</summary>
    class function AddUsesJson(const AUri, AText: string; const AUnits: TArray<string>;
      const AUses: TUsesContext; ATarget: TUsesAddTarget): TJSONObject; overload; static;
    function ExecuteUnits: TJSONValue;
    function ExecutePreview(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Argumente: [uri der Zieldatei, [Unit-Namen], optional {"section": "interface" |
    /// "implementation"}].</summary>
    function ExecuteAddUses(const AArguments: TJSONArray): TJSONValue;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.DateUtils,
  System.Generics.Defaults,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Lsp.Positions,
  Atlas.Text.Lines;

const
  TypeKinds: set of TIndexSymbolKind = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType,
    TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias];

function KindName(AKind: TIndexSymbolKind): string;
begin
  case AKind of
    TIndexSymbolKind.ClassType: Result := 'class';
    TIndexSymbolKind.ObjectType: Result := 'object';
    TIndexSymbolKind.RecordType: Result := 'record';
    TIndexSymbolKind.InterfaceType: Result := 'interface';
    TIndexSymbolKind.HelperType: Result := 'helper';
    TIndexSymbolKind.EnumType: Result := 'enum';
  else
    Result := 'type';
  end;
end;

function HasUses(const AUnit: TUnitIndex; const AName: string): Boolean;
var
  Name: string;
begin
  for Name in AUnit.InterfaceUses do
    if SameText(Name, AName) then
      Exit(True);
  for Name in AUnit.ImplementationUses do
    if SameText(Name, AName) then
      Exit(True);
  Result := False;
end;

{ TUnitSearch }

constructor TUnitSearch.Create(const AContextFor: TUnitSearchContextProvider);
begin
  inherited Create;
  FContextFor := AContextFor;
end;

class function TUnitSearch.KindOf(const AUnit: TUnitIndex; const AAncestorsOf: TFunc<string, TArray<string>>;
  AHasForm, AOnlyTestProjects: Boolean): string;
var
  Symbol: TIndexSymbol;
  Current, Upper: string;
  Ancestors: TArray<string>;
  Seen: TDictionary<string, Boolean>;
  Depth: Integer;
begin
  if HasUses(AUnit, 'DUnitX.TestFramework') or HasUses(AUnit, 'TestFramework') or AOnlyTestProjects then
    Exit('test');
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Symbol in AUnit.Symbols do
    begin
      if not Symbol.InInterface or (Symbol.Container <> '') or (Symbol.Kind <> TIndexSymbolKind.ClassType) or
        (Length(Symbol.Ancestors) = 0) then
        Continue;
      Current := Symbol.Ancestors[0];
      Seen.Clear;
      for Depth := 1 to 16 do
      begin
        // Qualifizierte Namen (Vcl.Forms.TForm) auf den letzten Teil kürzen.
        if Pos('.', Current) > 0 then
          Current := Copy(Current, LastDelimiter('.', Current) + 1, MaxInt);
        Upper := UpperCase(Current);
        if (Upper = 'TFORM') or (Upper = 'TCUSTOMFORM') then
          Exit('form');
        if (Upper = 'TFRAME') or (Upper = 'TCUSTOMFRAME') then
          Exit('frame');
        if Upper = 'TDATAMODULE' then
          Exit('dm');
        if (Upper = '') or Seen.ContainsKey(Upper) or not Assigned(AAncestorsOf) then
          Break;
        Seen.Add(Upper, True);
        Ancestors := AAncestorsOf(Current);
        if Length(Ancestors) = 0 then
          Break;
        Current := Ancestors[0];
      end;
    end;
  finally
    Seen.Free;
  end;
  if AHasForm then
    Result := 'form'
  else
    Result := 'unit';
end;

class function TUnitSearch.FormFileOf(const AFileName: string; const AExists: TFunc<string, Boolean>): string;
var
  Extension: string;
begin
  Result := '';
  if not Assigned(AExists) then
    Exit;
  for Extension in TArray<string>.Create('.dfm', '.fmx') do
    if AExists(ChangeFileExt(AFileName, Extension)) then
      Exit(ChangeFileExt(AFileName, Extension));
end;

class function TUnitSearch.HeaderComment(const AText: string): string;
var
  Lines, Output: TArray<string>;
  Line, Part: string;
  InBrace, InParen: Boolean;
  Index, Stop: Integer;
begin
  Lines := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  Output := nil;
  InBrace := False;
  InParen := False;
  for Index := 0 to High(Lines) do
  begin
    Line := Trim(Lines[Index]);
    if InBrace or InParen then
    begin
      if InBrace then
        Stop := Pos('}', Line)
      else
        Stop := Pos('*)', Line);
      if Stop > 0 then
      begin
        Part := Trim(Copy(Line, 1, Stop - 1));
        InBrace := False;
        InParen := False;
      end
      else
        Part := Line;
      Output := Output + [Part];
      Continue;
    end;
    if Line = '' then
    begin
      if Length(Output) > 0 then
        Output := Output + [''];
      Continue;
    end;
    if Line.StartsWith('{$') then
      Continue;
    if Line.StartsWith('//') then
    begin
      Part := Trim(Copy(Line, 3, MaxInt));
      // "///" und Trennlinien aus Strichen weglassen.
      while Part.StartsWith('/') do
        Part := Trim(Copy(Part, 2, MaxInt));
      if (Part <> '') and (Part.Replace('-', '').Replace('=', '').Replace('*', '') = '') then
        Continue;
      Output := Output + [Part];
      Continue;
    end;
    if Line.StartsWith('{') then
    begin
      Stop := Pos('}', Line);
      if Stop > 0 then
        Output := Output + [Trim(Copy(Line, 2, Stop - 2))]
      else
      begin
        Output := Output + [Trim(Copy(Line, 2, MaxInt))];
        InBrace := True;
      end;
      Continue;
    end;
    if Line.StartsWith('(*') then
    begin
      Stop := Pos('*)', Line);
      if Stop > 0 then
        Output := Output + [Trim(Copy(Line, 3, Stop - 3))]
      else
      begin
        Output := Output + [Trim(Copy(Line, 3, MaxInt))];
        InParen := True;
      end;
      Continue;
    end;
    // Erstes echtes Wort: unit, program usw.; der Kopf ist vorbei.
    Break;
  end;
  // Leere Zeilen am Anfang und Ende weg, dann kürzen.
  while (Length(Output) > 0) and (Output[High(Output)] = '') do
    SetLength(Output, Length(Output) - 1);
  while (Length(Output) > 0) and (Output[0] = '') do
    Delete(Output, 0, 1);
  if Length(Output) > MaxHeaderLines then
  begin
    SetLength(Output, MaxHeaderLines);
    Output[High(Output)] := Output[High(Output)] + ' …';
  end;
  Result := string.Join(#10, Output);
end;

class function TUnitSearch.LineCount(const AText: string): Integer;
var
  Index: Integer;
begin
  if AText = '' then
    Exit(0);
  Result := 1;
  for Index := 1 to Length(AText) do
    if AText[Index] = #10 then
      Inc(Result);
  if AText[Length(AText)] = #10 then
    Dec(Result);
end;

class function TUnitSearch.GitState(const ALines: TArray<string>; AInRepo: Boolean): string;
var
  Line, Code: string;
begin
  if not AInRepo then
    Exit('');
  Result := 'clean';
  for Line in ALines do
  begin
    if Length(Line) < 2 then
      Continue;
    Code := Copy(Line, 1, 2);
    if Code = '??' then
      Exit('untracked');
    if (Code = 'UU') or (Code = 'AA') or (Code = 'DD') or (Pos('U', Code) > 0) then
      Exit('conflict');
    if Pos('R', Code) > 0 then
      Exit('renamed');
    if Code[1] = 'A' then
      Exit('added');
    if Pos('D', Code) > 0 then
      Exit('deleted');
    if Pos('M', Code) > 0 then
      Exit('modified');
  end;
end;

function PropertyValue(AObject: TDfmObject; const AName: string; out AValue: string): Boolean;
var
  Item: TDfmProperty;
begin
  for Item in AObject.Properties do
    if SameText(Item.Name, AName) then
    begin
      AValue := Item.Value;
      Exit(True);
    end;
  AValue := '';
  Result := False;
end;

function IntValue(AObject: TDfmObject; const AName: string; ADefault: Integer): Integer;
var
  Value: string;
begin
  if not PropertyValue(AObject, AName, Value) or not TryStrToInt(Trim(Value), Result) then
    Result := ADefault;
end;

function TextValue(AObject: TDfmObject; const AName: string): string;
begin
  if not PropertyValue(AObject, AName, Result) then
    Exit('');
  Result := Trim(Result);
  // 'Text' bzw. 'Te'#39'xt': nur der einfache Fall, sonst roh gekürzt.
  if (Length(Result) >= 2) and Result.StartsWith('''') and Result.EndsWith('''') and
    (Pos('''', Copy(Result, 2, Length(Result) - 2)) = 0) then
    Result := Copy(Result, 2, Length(Result) - 2);
  if Length(Result) > 40 then
    Result := Copy(Result, 1, 40) + '…';
end;

type
  /// <summary>Rechteck der Skizze; ohne System.Types, damit Atlas.Common nichts von Windows braucht.</summary>
  TSketchBox = record
    Left, Top, Right, Bottom: Integer;
  end;

function Box(ALeft, ATop, ARight, ABottom: Integer): TSketchBox;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ARight;
  Result.Bottom := ABottom;
end;

procedure AddChildren(AParent: TDfmObject; const AClient: TSketchBox; ADepth: Integer;
  var AItems: TArray<TUnitSketchItem>);
var
  Child: TDfmObject;
  Item: TUnitSketchItem;
  Align, Dummy: string;
  Rest, Area: TSketchBox;
  Width_, Height_: Integer;
begin
  Rest := AClient;
  for Child in AParent.Children do
  begin
    if Length(AItems) >= TUnitSearch.MaxSketchItems then
      Exit;
    if Child.Kind = TDfmObjectKind.Item then
      Continue;
    Width_ := IntValue(Child, 'Width', IntValue(Child, 'ExplicitWidth', 75));
    Height_ := IntValue(Child, 'Height', IntValue(Child, 'ExplicitHeight', 25));
    Area.Left := AClient.Left + IntValue(Child, 'Left', 0);
    Area.Top := AClient.Top + IntValue(Child, 'Top', 0);
    Area.Right := Area.Left + Width_;
    Area.Bottom := Area.Top + Height_;
    PropertyValue(Child, 'Align', Align);
    Align := LowerCase(Trim(Align));
    // Ausrichtung in Reihenfolge der Datei vom Rest der Fläche abziehen.
    if Align = 'altop' then
    begin
      Area := Box(Rest.Left, Rest.Top, Rest.Right, Rest.Top + Height_);
      Rest.Top := Area.Bottom;
    end
    else if Align = 'albottom' then
    begin
      Area := Box(Rest.Left, Rest.Bottom - Height_, Rest.Right, Rest.Bottom);
      Rest.Bottom := Area.Top;
    end
    else if Align = 'alleft' then
    begin
      Area := Box(Rest.Left, Rest.Top, Rest.Left + Width_, Rest.Bottom);
      Rest.Left := Area.Right;
    end
    else if Align = 'alright' then
    begin
      Area := Box(Rest.Right - Width_, Rest.Top, Rest.Right, Rest.Bottom);
      Rest.Right := Area.Left;
    end
    else if Align = 'alclient' then
      Area := Rest;
    // Nicht sichtbare Komponenten (TTimer, TDataSource …) haben weder Lage noch Größe in der Datei.
    if PropertyValue(Child, 'Width', Dummy) or PropertyValue(Child, 'Height', Dummy) or
      PropertyValue(Child, 'Left', Dummy) or (Align <> '') then
    begin
      Item := Default(TUnitSketchItem);
      Item.Name := Child.Name;
      Item.TypeName := Child.TypeName;
      Item.Caption := TextValue(Child, 'Caption');
      if Item.Caption = '' then
        Item.Caption := TextValue(Child, 'Text');
      Item.Left := Area.Left;
      Item.Top := Area.Top;
      Item.Width := Max(0, Area.Right - Area.Left);
      Item.Height := Max(0, Area.Bottom - Area.Top);
      Item.Depth := ADepth;
      AItems := AItems + [Item];
      AddChildren(Child, Area, ADepth + 1, AItems);
    end;
  end;
end;

class function TUnitSearch.Sketch(const AFormText: string): TUnitSketch;
var
  Model: TFormModel;
  Root: TDfmObject;
begin
  Result := Default(TUnitSketch);
  if AFormText = '' then
    Exit;
  Model := TFormModel.Create(AFormText);
  try
    Root := Model.Document.Root;
    if Root = nil then
      Exit;
    Result.FormClass := Root.TypeName;
    Result.Caption := TextValue(Root, 'Caption');
    Result.Width := IntValue(Root, 'ClientWidth', IntValue(Root, 'Width', 640));
    Result.Height := IntValue(Root, 'ClientHeight', IntValue(Root, 'Height', 480));
    AddChildren(Root, Box(0, 0, Result.Width, Result.Height), 1, Result.Items);
  finally
    Model.Free;
  end;
end;

class function TUnitSearch.UsedBy(const AUnits: TArray<TUnitIndex>; const AUnitName: string): TArray<string>;
var
  Item: TUnitIndex;
  Names: TList<string>;
begin
  Names := TList<string>.Create;
  try
    for Item in AUnits do
      if not Item.Library_ and not SameText(Item.UnitName, AUnitName) and HasUses(Item, AUnitName) and
        not Names.Contains(Item.UnitName) then
        Names.Add(Item.UnitName);
    Names.Sort(TComparer<string>.Construct(
      function(const A, B: string): Integer
      begin
        Result := CompareText(A, B);
      end));
    Result := Names.ToArray;
  finally
    Names.Free;
  end;
end;

class function TUnitSearch.UnitsJson(const AContext: TUnitSearchContext): TJSONObject;
var
  Owners: TObjectDictionary<string, TList<Integer>>;
  Seen: TDictionary<string, Boolean>;
  Items: TJSONArray;
  ProjectList: TJSONArray;
  Project: TUnitSearchProject;
  ProjectIndex: Integer;
  FileName, Key, Origin, Kind, Include: string;
  Item: TUnitIndex;
  Entry: TJSONObject;
  Indices: TList<Integer>;
  OnlyTests, InProject: Boolean;

  function Projects(const AKey: string; out AOnlyTests: Boolean): TJSONArray;
  var
    List: TList<Integer>;
    Index: Integer;
  begin
    Result := TJSONArray.Create;
    AOnlyTests := False;
    if not Owners.TryGetValue(AKey, List) then
      Exit;
    AOnlyTests := True;
    for Index in List do
    begin
      Result.Add(AContext.Projects[Index].Name);
      if not AContext.Projects[Index].IsTest then
        AOnlyTests := False;
    end;
  end;

  procedure AddEntry(const AName, AFile, AOrigin, AKind: string; AProjects: TJSONArray);
  begin
    Entry := TJSONObject.Create;
    Entry.AddPair('name', AName);
    Entry.AddPair('uri', TDocumentUris.FromPath(AFile));
    Entry.AddPair('origin', AOrigin);
    Entry.AddPair('kind', AKind);
    Entry.AddPair('projects', AProjects);
    Items.Add(Entry);
  end;

begin
  Result := TJSONObject.Create;
  Items := TJSONArray.Create;
  Result.AddPair('units', Items);
  ProjectList := TJSONArray.Create;
  Result.AddPair('projects', ProjectList);
  Owners := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  Seen := TDictionary<string, Boolean>.Create;
  try
    for ProjectIndex := 0 to High(AContext.Projects) do
    begin
      Project := AContext.Projects[ProjectIndex];
      Entry := TJSONObject.Create;
      Entry.AddPair('name', Project.Name);
      if Project.FileName <> '' then
        Entry.AddPair('uri', TDocumentUris.FromPath(Project.FileName));
      Entry.AddPair('isTest', TJSONBool.Create(Project.IsTest));
      ProjectList.Add(Entry);
      for FileName in Project.Files do
      begin
        Key := UpperCase(FileName);
        if not Owners.TryGetValue(Key, Indices) then
        begin
          Indices := TList<Integer>.Create;
          Owners.Add(Key, Indices);
        end;
        if not Indices.Contains(ProjectIndex) then
          Indices.Add(ProjectIndex);
      end;
    end;
    for Item in AContext.Units do
    begin
      if (Item.UnitName = '') or (Item.FileName = '') then
        Continue;
      // Nur Units, keine Programme oder Packages.
      if not SameText(ExtractFileExt(Item.FileName), '.pas') then
        Continue;
      Key := UpperCase(Item.FileName);
      if Seen.ContainsKey(Key) then
        Continue;
      Seen.Add(Key, True);
      InProject := Owners.ContainsKey(Key);
      if InProject then
        Origin := 'project'
      else if Item.Library_ then
        Origin := 'library'
      else
        Origin := 'searchPath';
      ProjectList := Projects(Key, OnlyTests);
      AddEntry(Item.UnitName, Item.FileName, Origin,
        KindOf(Item, AContext.AncestorsOf, FormFileOf(Item.FileName, AContext.Exists) <> '', InProject and OnlyTests),
        ProjectList);
      // Include-Dateien der Projekt-Units (#264) als eigene Einträge.
      if not Item.Library_ then
        for Include in Item.Includes do
        begin
          if Seen.ContainsKey(UpperCase(Include)) then
            Continue;
          Seen.Add(UpperCase(Include), True);
          AddEntry(ExtractFileName(Include), Include, Origin, 'inc', Projects(Key, OnlyTests));
        end;
    end;
    // Projektdateien, die (noch) nicht im Index stehen.
    for ProjectIndex := 0 to High(AContext.Projects) do
      for FileName in AContext.Projects[ProjectIndex].Files do
      begin
        Key := UpperCase(FileName);
        if Seen.ContainsKey(Key) or not SameText(ExtractFileExt(FileName), '.pas') then
          Continue;
        Seen.Add(Key, True);
        ProjectList := Projects(Key, OnlyTests);
        if OnlyTests then
          Kind := 'test'
        else if FormFileOf(FileName, AContext.Exists) <> '' then
          Kind := 'form'
        else
          Kind := 'unit';
        AddEntry(ChangeFileExt(ExtractFileName(FileName), ''), FileName, 'project', Kind, ProjectList);
      end;
  finally
    Seen.Free;
    Owners.Free;
  end;
  Result.AddPair('count', TJSONNumber.Create(Items.Count));
end;

class function TUnitSearch.PreviewJson(const AContext: TUnitSearchContext; const AFileName: string;
  AWithForm, AWithUsedBy: Boolean): TJSONObject;
var
  Item, Found: TUnitIndex;
  HasUnit: Boolean;
  Text, FormFile, State: string;
  Types, Used, Components, UsesList: TJSONArray;
  Symbol: TIndexSymbol;
  Entry: TJSONObject;
  Names: TArray<string>;
  Name: string;
  Sketch_: TUnitSketch;
  SketchItem: TUnitSketchItem;
  Modified: TDateTime;
  TypeCount: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uri', TDocumentUris.FromPath(AFileName));
  HasUnit := False;
  Found := Default(TUnitIndex);
  for Item in AContext.Units do
    if SameText(Item.FileName, AFileName) then
    begin
      Found := Item;
      HasUnit := True;
      Break;
    end;
  if Assigned(AContext.ReadText) then
    Text := AContext.ReadText(AFileName)
  else
    Text := '';
  Result.AddPair('header', HeaderComment(Text));
  Result.AddPair('lines', TJSONNumber.Create(LineCount(Text)));
  Modified := 0;
  if Assigned(AContext.Modified) then
    Modified := AContext.Modified(AFileName);
  if Modified > 0 then
    Result.AddPair('modified', DateToISO8601(Modified, False));
  State := '';
  if Assigned(AContext.GitState) then
    State := AContext.GitState(AFileName);
  Result.AddPair('git', State);
  Types := TJSONArray.Create;
  Result.AddPair('types', Types);
  TypeCount := 0;
  if HasUnit then
  begin
    Result.AddPair('unit', Found.UnitName);
    for Symbol in Found.Symbols do
      if Symbol.InInterface and (Symbol.Container = '') and (Symbol.Kind in TypeKinds) then
      begin
        Inc(TypeCount);
        if Types.Count >= MaxTypes then
          Continue;
        Entry := TJSONObject.Create;
        Entry.AddPair('name', Symbol.Name);
        Entry.AddPair('kind', KindName(Symbol.Kind));
        if Length(Symbol.Ancestors) > 0 then
          Entry.AddPair('ancestor', Symbol.Ancestors[0]);
        Types.Add(Entry);
      end;
    // uses beider Abschnitte (#876), doppelte nur einmal.
    UsesList := TJSONArray.Create;
    Names := nil;
    for Name in Found.InterfaceUses + Found.ImplementationUses do
      if not MatchText(Name, Names) then
      begin
        Names := Names + [Name];
        UsesList.Add(Name);
      end;
    Result.AddPair('uses', UsesList);
  end;
  Result.AddPair('typeCount', TJSONNumber.Create(TypeCount));
  if AWithUsedBy and HasUnit then
  begin
    Names := UsedBy(AContext.Units, Found.UnitName);
    Used := TJSONArray.Create;
    for Name in Names do
      if Used.Count < MaxUsedBy then
        Used.Add(Name);
    Result.AddPair('usedBy', TJSONNumber.Create(Length(Names)));
    Result.AddPair('usedByUnits', Used);
  end;
  FormFile := FormFileOf(AFileName, AContext.Exists);
  if AWithForm and (FormFile <> '') and Assigned(AContext.ReadText) then
  begin
    Sketch_ := Sketch(AContext.ReadText(FormFile));
    if Sketch_.FormClass <> '' then
    begin
      Entry := TJSONObject.Create;
      Entry.AddPair('class', Sketch_.FormClass);
      Entry.AddPair('caption', Sketch_.Caption);
      Entry.AddPair('width', TJSONNumber.Create(Sketch_.Width));
      Entry.AddPair('height', TJSONNumber.Create(Sketch_.Height));
      Components := TJSONArray.Create;
      for SketchItem in Sketch_.Items do
        Components.Add(TJSONArray.Create.Add(SketchItem.Name).Add(SketchItem.TypeName).Add(SketchItem.Caption)
          .Add(SketchItem.Left).Add(SketchItem.Top).Add(SketchItem.Width).Add(SketchItem.Height)
          .Add(SketchItem.Depth));
      Entry.AddPair('items', Components);
      Result.AddPair('form', Entry);
    end;
  end;
end;

function TUnitSearch.ExecuteUnits: TJSONValue;
var
  Context: TUnitSearchContext;
begin
  if not FContextFor(Context) then
    Exit(TJSONNull.Create);
  Result := UnitsJson(Context);
end;

function TUnitSearch.ExecutePreview(const AArguments: TJSONArray): TJSONValue;
var
  Context: TUnitSearchContext;
  WithForm, WithUsedBy: Boolean;
  Options: TJSONObject;
begin
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONString) then
    Exit(TJSONNull.Create);
  WithForm := True;
  WithUsedBy := True;
  if (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
  begin
    Options := TJSONObject(AArguments.Items[1]);
    Options.TryGetValue<Boolean>('form', WithForm);
    Options.TryGetValue<Boolean>('usedBy', WithUsedBy);
  end;
  if not FContextFor(Context) then
    Exit(TJSONNull.Create);
  Result := PreviewJson(Context, TDocumentUris.ToPath(AArguments.Items[0].Value), WithForm, WithUsedBy);
end;

class function TUnitSearch.AddUsesJson(const AUri, AText: string; const AUnits: TArray<string>;
  const AUses: TUsesContext): TJSONObject;
begin
  Result := AddUsesJson(AUri, AText, AUnits, AUses, TUsesAddTarget.Auto);
end;

class function TUnitSearch.AddUsesJson(const AUri, AText: string; const AUnits: TArray<string>;
  const AUses: TUsesContext; ATarget: TUsesAddTarget): TJSONObject;
var
  Edits: TArray<TRuleEdit>;
  Edit: TRuleEdit;
  Added: TArray<string>;
  Name, LineBreak: string;
  Changes, WorkspaceEdit, Item: TJSONObject;
  List, AddedList: TJSONArray;
begin
  Result := TJSONObject.Create;
  LineBreak := TTextLines.LineBreakOf(AText);
  AddedList := TJSONArray.Create;
  if (AText <> '') and TUsesActions.AddUnits(TPascalLexer.Tokenize(AText), AUnits, AUses.Declaring,
    AUses.Namespaces, ATarget, LineBreak, Edits, Added) then
  begin
    List := TJSONArray.Create;
    for Edit in Edits do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
      Item.AddPair('newText', Edit.NewText);
      List.Add(Item);
    end;
    Changes := TJSONObject.Create;
    Changes.AddPair(AUri, List);
    WorkspaceEdit := TJSONObject.Create;
    WorkspaceEdit.AddPair('changes', Changes);
    Result.AddPair('edit', WorkspaceEdit);
    for Name in Added do
      AddedList.Add(Name);
  end
  else
    Result.AddPair('edit', TJSONNull.Create);
  Result.AddPair('added', AddedList);
end;

function TUnitSearch.ExecuteAddUses(const AArguments: TJSONArray): TJSONValue;
var
  Context: TUnitSearchContext;
  UsesContext: TUsesContext;
  Units: TArray<string>;
  Value, Section: TJSONValue;
  Uri: string;
  Target: TUsesAddTarget;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[0] is TJSONString) or
    not (AArguments.Items[1] is TJSONArray) then
    Exit(TJSONNull.Create);
  Units := nil;
  for Value in TJSONArray(AArguments.Items[1]) do
    if Value is TJSONString then
      Units := Units + [Value.Value];
  if not FContextFor(Context) or not Assigned(Context.ReadText) then
    Exit(TJSONNull.Create);
  Uri := AArguments.Items[0].Value;
  UsesContext := Default(TUsesContext);
  if Assigned(Context.UsesFor) then
    UsesContext := Context.UsesFor(Uri);
  Target := TUsesAddTarget.Auto;
  if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONObject) then
  begin
    Section := TJSONObject(AArguments.Items[2]).GetValue('section');
    if Section is TJSONString then
      if SameText(Section.Value, 'interface') then
        Target := TUsesAddTarget.Interface_
      else if SameText(Section.Value, 'implementation') then
        Target := TUsesAddTarget.Implementation_;
  end;
  Result := AddUsesJson(Uri, Context.ReadText(TDocumentUris.ToPath(Uri)), Units, UsesContext, Target);
end;

end.
