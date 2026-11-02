unit Atlas.Common.Lsp.UnitSearch;

// Daten für das Fenster „Units suchen“ des Plugins (#777):
//   - Befehl atlas.server.units [{captions}]: alle Units aus Index und
//     Projektmodell mit Datei, Projekten, Herkunft (project, searchPath,
//     library) und Art (form, frame, dm, unit, test, inc). Kein Dateizugriff
//     außer der Frage, ob eine Formulardatei neben der Unit liegt; mit
//     captions: true zusätzlich die Caption der Formulare (#1310) aus dem Kopf
//     der Formulardatei, je Datei bis zur nächsten Änderung zwischengespeichert.
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
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.Contract;

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
  private type
    TCaptionEntry = record
      Modified: TDateTime;
      Caption: string;
    end;
  private
    FContextFor: TUnitSearchContextProvider;
    /// <summary>Caption je Formulardatei (Großschrift) mit dem Änderungszeitpunkt beim Lesen.</summary>
    FCaptions: TDictionary<string, TCaptionEntry>;
    function CachedCaption(const AContext: TUnitSearchContext; const AFormFile: string): string;
    function CaptionsFor(const AContext: TUnitSearchContext): TFunc<string, string>;
  public
    constructor Create(const AContextFor: TUnitSearchContextProvider);
    destructor Destroy; override;
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
    /// <summary>Caption des Wurzelobjekts einer Text-DFM/-FMX (#1310); liest nur die Eigenschaften vor dem
    /// ersten Kindobjekt. '' ohne Caption und bei binären Dateien.</summary>
    class function FormCaption(const AFormText: string): string; static;
    /// <summary>Skizze aus der Formulardatei: absolute Lage aus Left/Top samt einfachem Align.</summary>
    class function Sketch(const AFormText: string): TUnitSketch; static;
    /// <summary>Namen der Units, die AUnitName in uses haben (ohne Bibliothek), sortiert.</summary>
    class function UsedBy(const AUnits: TArray<TUnitIndex>; const AUnitName: string): TArray<string>; static;
    /// <summary>Antwort auf atlas.server.units ohne Captions.</summary>
    class function UnitsJson(const AContext: TUnitSearchContext): TJSONObject; overload; static;
    /// <summary>Antwort auf atlas.server.units; ACaptionOf liefert zur Formulardatei die Caption (#1310), nil =
    /// keine.</summary>
    class function UnitsJson(const AContext: TUnitSearchContext; const ACaptionOf: TFunc<string, string>)
      : TJSONObject; overload; static;
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
    /// <summary>Argumente: [{captions: Boolean}] (optional, Standard ohne Captions).</summary>
    function ExecuteUnits(const AArguments: TJSONArray): TJSONValue;
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
  Atlas.Common.Editing.StringLiterals,
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
  begin
    if SameText(Name, AName) then
    begin
      Exit(True);
    end;
  end;
  for Name in AUnit.ImplementationUses do
  begin
    if SameText(Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TUnitSearch }

constructor TUnitSearch.Create(const AContextFor: TUnitSearchContextProvider);
begin
  inherited Create;
  FContextFor := AContextFor;
  FCaptions := TDictionary<string, TCaptionEntry>.Create;
end;

destructor TUnitSearch.Destroy;
begin
  FCaptions.Free;
  inherited;
end;

function IsObjectLine(const ATrimmed: string): Boolean;
begin
  Result := StartsText('object ', ATrimmed) or StartsText('inherited ', ATrimmed) or
    StartsText('inline ', ATrimmed);
end;

class function TUnitSearch.FormCaption(const AFormText: string): string;
var
  Lines: TArray<string>;
  Index, Indent, RootIndent: Integer;
  Line, Trimmed, Rest, Value: string;
begin
  Result := '';
  if (AFormText = '') or TFormModel.IsBinary(AFormText) then
  begin
    Exit;
  end;
  Lines := TTextLines.SplitLines(AFormText);
  Index := 0;
  while (Index <= High(Lines)) and (Trim(Lines[Index]) = '') do
  begin
    Inc(Index);
  end;
  if (Index > High(Lines)) or not IsObjectLine(Trim(Lines[Index])) then
  begin
    Exit;
  end;
  // Eigenschaften des Wurzelobjekts stehen vor seinen Kindobjekten und gleich weit eingerückt; tiefer
  // eingerückte Zeilen gehören zu Listen oder Collections.
  RootIndent := -1;
  Inc(Index);
  while Index <= High(Lines) do
  begin
    Line := Lines[Index];
    Trimmed := TrimLeft(Line);
    Indent := Length(Line) - Length(Trimmed);
    Trimmed := TrimRight(Trimmed);
    Inc(Index);
    if Trimmed = '' then
    begin
      Continue;
    end;
    if RootIndent < 0 then
    begin
      RootIndent := Indent;
    end;
    if (Indent < RootIndent) or ((Indent = RootIndent) and (IsObjectLine(Trimmed) or SameText(Trimmed, 'end'))) then
    begin
      Exit;
    end;
    if (Indent > RootIndent) or not StartsText('Caption', Trimmed) then
    begin
      Continue;
    end;
    Rest := TrimLeft(Copy(Trimmed, Length('Caption') + 1, MaxInt));
    if not StartsStr('=', Rest) then
    begin
      Continue;
    end;
    // Lange Werte setzt Delphi in Folgezeilen fort: "Caption =" allein oder Teile mit "+" am Ende.
    Value := Trim(Copy(Rest, 2, MaxInt));
    while ((Value = '') or EndsStr('+', Value)) and (Index <= High(Lines)) do
    begin
      Value := Value + ' ' + Trim(Lines[Index]);
      Inc(Index);
    end;
    if not TStringLiterals.PlainText(Value, Result) then
    begin
      Result := '';
    end;
    Exit;
  end;
end;

function TUnitSearch.CachedCaption(const AContext: TUnitSearchContext; const AFormFile: string): string;
var
  Key: string;
  Modified: TDateTime;
  Entry: TCaptionEntry;
begin
  Result := '';
  if (AFormFile = '') or not Assigned(AContext.ReadText) then
  begin
    Exit;
  end;
  Key := UpperCase(AFormFile);
  Modified := 0;
  if Assigned(AContext.Modified) then
  begin
    Modified := AContext.Modified(AFormFile);
  end;
  System.TMonitor.Enter(FCaptions);
  try
    if (Modified <> 0) and FCaptions.TryGetValue(Key, Entry) and (Entry.Modified = Modified) then
    begin
      Exit(Entry.Caption);
    end;
  finally
    System.TMonitor.Exit(FCaptions);
  end;
  Result := FormCaption(AContext.ReadText(AFormFile));
  // Ohne bekannten Zeitpunkt nicht merken: Die Datei könnte sich unbemerkt ändern.
  if Modified = 0 then
  begin
    Exit;
  end;
  Entry.Modified := Modified;
  Entry.Caption := Result;
  System.TMonitor.Enter(FCaptions);
  try
    FCaptions.AddOrSetValue(Key, Entry);
  finally
    System.TMonitor.Exit(FCaptions);
  end;
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
  begin
    Exit('test');
  end;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Symbol in AUnit.Symbols do
    begin
      if not Symbol.InInterface or (Symbol.Container <> '') or (Symbol.Kind <> TIndexSymbolKind.ClassType) or
        (Length(Symbol.Ancestors) = 0) then
      begin
        Continue;
      end;
      Current := Symbol.Ancestors[0];
      Seen.Clear;
      for Depth := 1 to 16 do
      begin
        // Qualifizierte Namen (Vcl.Forms.TForm) auf den letzten Teil kürzen.
        if Pos('.', Current) > 0 then
        begin
          Current := Copy(Current, LastDelimiter('.', Current) + 1, MaxInt);
        end;
        Upper := UpperCase(Current);
        if (Upper = 'TFORM') or (Upper = 'TCUSTOMFORM') then
        begin
          Exit('form');
        end;
        if (Upper = 'TFRAME') or (Upper = 'TCUSTOMFRAME') then
        begin
          Exit('frame');
        end;
        if Upper = 'TDATAMODULE' then
        begin
          Exit('dm');
        end;
        if (Upper = '') or Seen.ContainsKey(Upper) or not Assigned(AAncestorsOf) then
        begin
          Break;
        end;
        Seen.Add(Upper, True);
        Ancestors := AAncestorsOf(Current);
        if Length(Ancestors) = 0 then
        begin
          Break;
        end;
        Current := Ancestors[0];
      end;
    end;
  finally
    Seen.Free;
  end;
  if AHasForm then
  begin
    Result := 'form';
  end
  else
  begin
    Result := 'unit';
  end;
end;

class function TUnitSearch.FormFileOf(const AFileName: string; const AExists: TFunc<string, Boolean>): string;
var
  Extension: string;
begin
  Result := '';
  if not Assigned(AExists) then
  begin
    Exit;
  end;
  for Extension in TArray<string>.Create('.dfm', '.fmx') do
  begin
    if AExists(ChangeFileExt(AFileName, Extension)) then
    begin
      Exit(ChangeFileExt(AFileName, Extension));
    end;
  end;
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
      begin
        Stop := Pos('}', Line);
      end
      else
      begin
        Stop := Pos('*)', Line);
      end;
      if Stop > 0 then
      begin
        Part := Trim(Copy(Line, 1, Stop - 1));
        InBrace := False;
        InParen := False;
      end
      else
      begin
        Part := Line;
      end;
      Output := Output + [Part];
      Continue;
    end;
    if Line = '' then
    begin
      if Length(Output) > 0 then
      begin
        Output := Output + [''];
      end;
      Continue;
    end;
    if Line.StartsWith('{$') then
    begin
      Continue;
    end;
    if Line.StartsWith('//') then
    begin
      Part := Trim(Copy(Line, 3, MaxInt));
      // "///" und Trennlinien aus Strichen weglassen.
      while Part.StartsWith('/') do
      begin
        Part := Trim(Copy(Part, 2, MaxInt));
      end;
      if (Part <> '') and (Part.Replace('-', '').Replace('=', '').Replace('*', '') = '') then
      begin
        Continue;
      end;
      Output := Output + [Part];
      Continue;
    end;
    if Line.StartsWith('{') then
    begin
      Stop := Pos('}', Line);
      if Stop > 0 then
      begin
        Output := Output + [Trim(Copy(Line, 2, Stop - 2))];
      end
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
      begin
        Output := Output + [Trim(Copy(Line, 3, Stop - 3))];
      end
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
  begin
    SetLength(Output, Length(Output) - 1);
  end;
  while (Length(Output) > 0) and (Output[0] = '') do
  begin
    Delete(Output, 0, 1);
  end;
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
  begin
    Exit(0);
  end;
  Result := 1;
  for Index := 1 to Length(AText) do
  begin
    if AText[Index] = #10 then
    begin
      Inc(Result);
    end;
  end;
  if AText[Length(AText)] = #10 then
  begin
    Dec(Result);
  end;
end;

class function TUnitSearch.GitState(const ALines: TArray<string>; AInRepo: Boolean): string;
var
  Line, Code: string;
begin
  if not AInRepo then
  begin
    Exit('');
  end;
  Result := 'clean';
  for Line in ALines do
  begin
    if Length(Line) < 2 then
    begin
      Continue;
    end;
    Code := Copy(Line, 1, 2);
    if Code = '??' then
    begin
      Exit('untracked');
    end;
    if (Code = 'UU') or (Code = 'AA') or (Code = 'DD') or (Pos('U', Code) > 0) then
    begin
      Exit('conflict');
    end;
    if Pos('R', Code) > 0 then
    begin
      Exit('renamed');
    end;
    if Code[1] = 'A' then
    begin
      Exit('added');
    end;
    if Pos('D', Code) > 0 then
    begin
      Exit('deleted');
    end;
    if Pos('M', Code) > 0 then
    begin
      Exit('modified');
    end;
  end;
end;

function PropertyValue(AObject: TDfmObject; const AName: string; out AValue: string): Boolean;
var
  Item: TDfmProperty;
begin
  for Item in AObject.Properties do
  begin
    if SameText(Item.Name, AName) then
    begin
      AValue := Item.Value;
      Exit(True);
    end;
  end;
  AValue := '';
  Result := False;
end;

function IntValue(AObject: TDfmObject; const AName: string; ADefault: Integer): Integer;
var
  Value: string;
begin
  if not PropertyValue(AObject, AName, Value) or not TryStrToInt(Trim(Value), Result) then
  begin
    Result := ADefault;
  end;
end;

function TextValue(AObject: TDfmObject; const AName: string): string;
begin
  if not PropertyValue(AObject, AName, Result) then
  begin
    Exit('');
  end;
  Result := Trim(Result);
  // 'Text' bzw. 'Te'#39'xt': nur der einfache Fall, sonst roh gekürzt.
  if (Length(Result) >= 2) and Result.StartsWith('''') and Result.EndsWith('''') and
    (Pos('''', Copy(Result, 2, Length(Result) - 2)) = 0) then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
  if Length(Result) > 40 then
  begin
    Result := Copy(Result, 1, 40) + '…';
  end;
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
    begin
      Exit;
    end;
    if Child.Kind = TDfmObjectKind.Item then
    begin
      Continue;
    end;
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
    begin
      Area := Rest;
    end;
    // Nicht sichtbare Komponenten (TTimer, TDataSource …) haben weder Lage noch Größe in der Datei.
    if PropertyValue(Child, 'Width', Dummy) or PropertyValue(Child, 'Height', Dummy) or
      PropertyValue(Child, 'Left', Dummy) or (Align <> '') then
    begin
      Item := Default(TUnitSketchItem);
      Item.Name := Child.Name;
      Item.TypeName := Child.TypeName;
      Item.Caption := TextValue(Child, 'Caption');
      if Item.Caption = '' then
      begin
        Item.Caption := TextValue(Child, 'Text');
      end;
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
  begin
    Exit;
  end;
  Model := TFormModel.Create(AFormText);
  try
    Root := Model.Document.Root;
    if Root = nil then
    begin
      Exit;
    end;
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
    begin
      if not Item.Library_ and not SameText(Item.UnitName, AUnitName) and HasUses(Item, AUnitName) and
        not Names.Contains(Item.UnitName) then
      begin
        Names.Add(Item.UnitName);
      end;
    end;
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

function TUnitSearch.CaptionsFor(const AContext: TUnitSearchContext): TFunc<string, string>;
var
  Context: TUnitSearchContext;
begin
  Context := AContext;
  Result :=
    function(AFormFile: string): string
    begin
      Result := CachedCaption(Context, AFormFile);
    end;
end;

class function TUnitSearch.UnitsJson(const AContext: TUnitSearchContext): TJSONObject;
begin
  Result := UnitsJson(AContext, nil);
end;

class function TUnitSearch.UnitsJson(const AContext: TUnitSearchContext; const ACaptionOf: TFunc<string, string>)
  : TJSONObject;
var
  Owners: TObjectDictionary<string, TList<Integer>>;
  Seen: TDictionary<string, Boolean>;
  Items: TJSONArray;
  ProjectList: TJSONArray;
  Project: TUnitSearchProject;
  ProjectIndex: Integer;
  FileName, Key, Origin, Kind, Include, FormFile, Caption: string;
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
    begin
      Exit;
    end;
    AOnlyTests := True;
    for Index in List do
    begin
      Result.Add(AContext.Projects[Index].Name);
      if not AContext.Projects[Index].IsTest then
      begin
        AOnlyTests := False;
      end;
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

  procedure AddCaption(const AKind, AOrigin, AFormFile: string);
  begin
    // Nur Formulare außerhalb der Bibliothek (#1310): Frames und Datenmodule haben keine sichtbare Caption.
    if not Assigned(ACaptionOf) or (AKind <> 'form') or (AOrigin = 'library') or (AFormFile = '') then
    begin
      Exit;
    end;
    Caption := ACaptionOf(AFormFile);
    if Caption <> '' then
    begin
      Entry.AddPair('caption', Caption);
    end;
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
      begin
        Entry.AddPair('uri', TDocumentUris.FromPath(Project.FileName));
      end;
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
        begin
          Indices.Add(ProjectIndex);
        end;
      end;
    end;
    for Item in AContext.Units do
    begin
      if (Item.UnitName = '') or (Item.FileName = '') then
      begin
        Continue;
      end;
      // Nur Units, keine Programme oder Packages.
      if not SameText(ExtractFileExt(Item.FileName), '.pas') then
      begin
        Continue;
      end;
      Key := UpperCase(Item.FileName);
      if Seen.ContainsKey(Key) then
      begin
        Continue;
      end;
      Seen.Add(Key, True);
      InProject := Owners.ContainsKey(Key);
      if InProject then
      begin
        Origin := 'project';
      end
      else if Item.Library_ then
      begin
        Origin := 'library';
      end
      else
      begin
        Origin := 'searchPath';
      end;
      ProjectList := Projects(Key, OnlyTests);
      FormFile := FormFileOf(Item.FileName, AContext.Exists);
      Kind := KindOf(Item, AContext.AncestorsOf, FormFile <> '', InProject and OnlyTests);
      AddEntry(Item.UnitName, Item.FileName, Origin, Kind, ProjectList);
      AddCaption(Kind, Origin, FormFile);
      // Include-Dateien der Projekt-Units (#264) als eigene Einträge.
      if not Item.Library_ then
      begin
        for Include in Item.Includes do
        begin
          if Seen.ContainsKey(UpperCase(Include)) then
          begin
            Continue;
          end;
          Seen.Add(UpperCase(Include), True);
          AddEntry(ExtractFileName(Include), Include, Origin, 'inc', Projects(Key, OnlyTests));
        end;
      end;
    end;
    // Projektdateien, die (noch) nicht im Index stehen.
    for ProjectIndex := 0 to High(AContext.Projects) do
    begin
      for FileName in AContext.Projects[ProjectIndex].Files do
      begin
        Key := UpperCase(FileName);
        if Seen.ContainsKey(Key) or not SameText(ExtractFileExt(FileName), '.pas') then
        begin
          Continue;
        end;
        Seen.Add(Key, True);
        ProjectList := Projects(Key, OnlyTests);
        FormFile := FormFileOf(FileName, AContext.Exists);
        if OnlyTests then
        begin
          Kind := 'test';
        end
        else if FormFile <> '' then
        begin
          Kind := 'form';
        end
        else
        begin
          Kind := 'unit';
        end;
        AddEntry(ChangeFileExt(ExtractFileName(FileName), ''), FileName, 'project', Kind, ProjectList);
        AddCaption(Kind, 'project', FormFile);
      end;
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
  begin
    if SameText(Item.FileName, AFileName) then
    begin
      Found := Item;
      HasUnit := True;
      Break;
    end;
  end;
  if Assigned(AContext.ReadText) then
  begin
    Text := AContext.ReadText(AFileName);
  end
  else
  begin
    Text := '';
  end;
  Result.AddPair('header', HeaderComment(Text));
  Result.AddPair('lines', TJSONNumber.Create(LineCount(Text)));
  Modified := 0;
  if Assigned(AContext.Modified) then
  begin
    Modified := AContext.Modified(AFileName);
  end;
  if Modified > 0 then
  begin
    Result.AddPair('modified', DateToISO8601(Modified, False));
  end;
  State := '';
  if Assigned(AContext.GitState) then
  begin
    State := AContext.GitState(AFileName);
  end;
  Result.AddPair('git', State);
  Types := TJSONArray.Create;
  Result.AddPair('types', Types);
  TypeCount := 0;
  if HasUnit then
  begin
    Result.AddPair('unit', Found.UnitName);
    for Symbol in Found.Symbols do
    begin
      if Symbol.InInterface and (Symbol.Container = '') and (Symbol.Kind in TypeKinds) then
      begin
        Inc(TypeCount);
        if Types.Count >= MaxTypes then
        begin
          Continue;
        end;
        Entry := TJSONObject.Create;
        Entry.AddPair('name', Symbol.Name);
        Entry.AddPair('kind', KindName(Symbol.Kind));
        if Length(Symbol.Ancestors) > 0 then
        begin
          Entry.AddPair('ancestor', Symbol.Ancestors[0]);
        end;
        Types.Add(Entry);
      end;
    end;
    // uses beider Abschnitte (#876), doppelte nur einmal.
    UsesList := TJSONArray.Create;
    Names := nil;
    for Name in Found.InterfaceUses + Found.ImplementationUses do
    begin
      if not MatchText(Name, Names) then
      begin
        Names := Names + [Name];
        UsesList.Add(Name);
      end;
    end;
    Result.AddPair('uses', UsesList);
  end;
  Result.AddPair('typeCount', TJSONNumber.Create(TypeCount));
  if AWithUsedBy and HasUnit then
  begin
    Names := UsedBy(AContext.Units, Found.UnitName);
    Used := TJSONArray.Create;
    for Name in Names do
    begin
      if Used.Count < MaxUsedBy then
      begin
        Used.Add(Name);
      end;
    end;
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
      begin
        Components.Add(TJSONArray.Create.Add(SketchItem.Name).Add(SketchItem.TypeName).Add(SketchItem.Caption)
          .Add(SketchItem.Left).Add(SketchItem.Top).Add(SketchItem.Width).Add(SketchItem.Height)
          .Add(SketchItem.Depth));
      end;
      Entry.AddPair('items', Components);
      Result.AddPair('form', Entry);
    end;
  end;
end;

function TUnitSearch.ExecuteUnits(const AArguments: TJSONArray): TJSONValue;
var
  Context: TUnitSearchContext;
  WithCaptions: Boolean;
begin
  WithCaptions := False;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONObject) then
  begin
    TJSONObject(AArguments.Items[0]).TryGetValue<Boolean>('captions', WithCaptions);
  end;
  if not FContextFor(Context) then
  begin
    Exit(TJSONNull.Create);
  end;
  if not WithCaptions then
  begin
    Exit(UnitsJson(Context));
  end;
  Result := UnitsJson(Context, CaptionsFor(Context));
end;

function TUnitSearch.ExecutePreview(const AArguments: TJSONArray): TJSONValue;
var
  Context: TUnitSearchContext;
  WithForm, WithUsedBy: Boolean;
  Options: TJSONObject;
begin
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONString) then
  begin
    Exit(TJSONNull.Create);
  end;
  WithForm := True;
  WithUsedBy := True;
  if (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
  begin
    Options := TJSONObject(AArguments.Items[1]);
    Options.TryGetValue<Boolean>('form', WithForm);
    Options.TryGetValue<Boolean>('usedBy', WithUsedBy);
  end;
  if not FContextFor(Context) then
  begin
    Exit(TJSONNull.Create);
  end;
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
    begin
      AddedList.Add(Name);
    end;
  end
  else
  begin
    Result.AddPair('edit', TJSONNull.Create);
  end;
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
  begin
    Exit(TJSONNull.Create);
  end;
  Units := nil;
  for Value in TJSONArray(AArguments.Items[1]) do
  begin
    if Value is TJSONString then
    begin
      Units := Units + [Value.Value];
    end;
  end;
  if not FContextFor(Context) or not Assigned(Context.ReadText) then
  begin
    Exit(TJSONNull.Create);
  end;
  Uri := AArguments.Items[0].Value;
  UsesContext := Default(TUsesContext);
  if Assigned(Context.UsesFor) then
  begin
    UsesContext := Context.UsesFor(Uri);
  end;
  Target := TUsesAddTarget.Auto;
  if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONObject) then
  begin
    Section := TJSONObject(AArguments.Items[2]).GetValue('section');
    if Section is TJSONString then
    begin
      if SameText(Section.Value, 'interface') then
      begin
        Target := TUsesAddTarget.Interface_;
      end
      else if SameText(Section.Value, 'implementation') then
      begin
        Target := TUsesAddTarget.Implementation_;
      end;
    end;
  end;
  Result := AddUsesJson(Uri, Context.ReadText(TDocumentUris.ToPath(Uri)), Units, UsesContext, Target);
end;

end.
