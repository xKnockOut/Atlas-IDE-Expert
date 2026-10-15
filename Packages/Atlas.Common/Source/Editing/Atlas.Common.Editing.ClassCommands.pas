unit Atlas.Common.Editing.ClassCommands;

// Schnellbefehle für Klassen (#295) im Rahmen aus #293:
//   /impl            fehlende Methodenrümpfe der Klasse anlegen
//   /ctor [owner]    Konstruktor mit den Feldern als Parametern; "owner" für Komponenten;
//                    "/ctor FName, FAlter" nur mit diesen Feldern (Auswahl im Erzeugen-Menü, #719)
//   /dtor            Destruktor, der im Konstruktor erzeugte Felder freigibt
//   /override Name   virtuelle Methode eines Vorfahren überschreiben (auch aus dem Index)
//   /msg WM_SIZE     Botschaftsmethode mit passendem Record
//
// Deklarationen kommen in einen eigenen Abschnitt vor "end" der Klasse, Rümpfe
// hinter die letzte Methode der Klasse. Für die Auswahl im Erzeugen-Menü (#719)
// liefern CtorFields, OverrideCandidates und MessageNames die möglichen
// Argumente.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.SlashCommands;

/// <summary>Trägt die Klassenbefehle in ARegistry ein.</summary>
procedure RegisterClassCommands(ARegistry: TSlashCommandRegistry);

/// <summary>Methodenname zur Botschaft: WM_SIZE wird zu WMSize, CM_MOUSEENTER zu CMMouseEnter (Tabelle, sonst je Teil groß).</summary>
function MessageMethodName(const AMessage: string): string;
/// <summary>Record-Typ zur Botschaft, TMessage ohne Eintrag in der Tabelle.</summary>
function MessageRecord(const AMessage: string): string;
/// <summary>Kopf "procedure Name(...)" bzw. "function Name(...): Typ" ohne Direktiven.</summary>
function RoutineSignature(const ADeclaration: string): string;
/// <summary>Parameternamen aus dem Kopf, kommagetrennt.</summary>
function ParameterNames(const ASignature: string): string;
/// <summary>Text in ARange aus ALines, Zeilen mit Leerzeichen verbunden.</summary>
function RangeText(const ALines: TArray<string>; const ARange: TTextRange): string;
function LoadText(const AFileName: string; out AText: string): Boolean;
/// <summary>Felder der Klasse um die Befehlszeile, die /ctor als Parameter nimmt (#719); leer außerhalb.</summary>
function CtorFields(const AContext: TSlashContext): TArray<string>;
/// <summary>Virtuelle Methoden der Vorfahren (Datei, dann Index), die die Klasse um die Befehlszeile noch nicht
/// selbst deklariert; Namen in der Reihenfolge der Vorfahren, ohne Doppelte (#719).</summary>
function OverrideCandidates(const AContext: TSlashContext): TArray<string>;
/// <summary>Botschaften der Tabelle, z. B. WM_SIZE (#719).</summary>
function MessageNames: TArray<string>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Common.Editing.CommandSource;

type
  TMessageEntry = record
    Name: string;
    Method: string;
    RecordType: string;
  end;

const
  // Häufige Botschaften mit Methodennamen wie in der VCL und Record aus Winapi.Messages bzw. Vcl.Controls.
  MessageTable: array[0..37] of TMessageEntry = (
    (Name: 'WM_SIZE'; Method: 'WMSize'; RecordType: 'TWMSize'),
    (Name: 'WM_MOVE'; Method: 'WMMove'; RecordType: 'TWMMove'),
    (Name: 'WM_PAINT'; Method: 'WMPaint'; RecordType: 'TWMPaint'),
    (Name: 'WM_ERASEBKGND'; Method: 'WMEraseBkgnd'; RecordType: 'TWMEraseBkgnd'),
    (Name: 'WM_KEYDOWN'; Method: 'WMKeyDown'; RecordType: 'TWMKeyDown'),
    (Name: 'WM_KEYUP'; Method: 'WMKeyUp'; RecordType: 'TWMKeyUp'),
    (Name: 'WM_CHAR'; Method: 'WMChar'; RecordType: 'TWMChar'),
    (Name: 'WM_LBUTTONDOWN'; Method: 'WMLButtonDown'; RecordType: 'TWMLButtonDown'),
    (Name: 'WM_LBUTTONUP'; Method: 'WMLButtonUp'; RecordType: 'TWMLButtonUp'),
    (Name: 'WM_MOUSEMOVE'; Method: 'WMMouseMove'; RecordType: 'TWMMouseMove'),
    (Name: 'WM_MOUSEWHEEL'; Method: 'WMMouseWheel'; RecordType: 'TWMMouseWheel'),
    (Name: 'WM_SETFOCUS'; Method: 'WMSetFocus'; RecordType: 'TWMSetFocus'),
    (Name: 'WM_KILLFOCUS'; Method: 'WMKillFocus'; RecordType: 'TWMKillFocus'),
    (Name: 'WM_TIMER'; Method: 'WMTimer'; RecordType: 'TWMTimer'),
    (Name: 'WM_COMMAND'; Method: 'WMCommand'; RecordType: 'TWMCommand'),
    (Name: 'WM_NOTIFY'; Method: 'WMNotify'; RecordType: 'TWMNotify'),
    (Name: 'WM_GETMINMAXINFO'; Method: 'WMGetMinMaxInfo'; RecordType: 'TWMGetMinMaxInfo'),
    (Name: 'WM_NCHITTEST'; Method: 'WMNCHitTest'; RecordType: 'TWMNCHitTest'),
    (Name: 'WM_DROPFILES'; Method: 'WMDropFiles'; RecordType: 'TWMDropFiles'),
    (Name: 'WM_CLOSE'; Method: 'WMClose'; RecordType: 'TWMClose'),
    (Name: 'WM_SYSCOMMAND'; Method: 'WMSysCommand'; RecordType: 'TWMSysCommand'),
    (Name: 'WM_CONTEXTMENU'; Method: 'WMContextMenu'; RecordType: 'TWMContextMenu'),
    (Name: 'WM_SETCURSOR'; Method: 'WMSetCursor'; RecordType: 'TWMSetCursor'),
    (Name: 'WM_SHOWWINDOW'; Method: 'WMShowWindow'; RecordType: 'TWMShowWindow'),
    (Name: 'CM_MOUSEENTER'; Method: 'CMMouseEnter'; RecordType: 'TMessage'),
    (Name: 'CM_MOUSELEAVE'; Method: 'CMMouseLeave'; RecordType: 'TMessage'),
    (Name: 'CM_FONTCHANGED'; Method: 'CMFontChanged'; RecordType: 'TMessage'),
    (Name: 'CM_COLORCHANGED'; Method: 'CMColorChanged'; RecordType: 'TMessage'),
    (Name: 'CM_ENABLEDCHANGED'; Method: 'CMEnabledChanged'; RecordType: 'TMessage'),
    (Name: 'CM_TEXTCHANGED'; Method: 'CMTextChanged'; RecordType: 'TMessage'),
    (Name: 'CM_VISIBLECHANGED'; Method: 'CMVisibleChanged'; RecordType: 'TMessage'),
    (Name: 'CM_DIALOGKEY'; Method: 'CMDialogKey'; RecordType: 'TCMDialogKey'),
    (Name: 'CM_DIALOGCHAR'; Method: 'CMDialogChar'; RecordType: 'TCMDialogChar'),
    (Name: 'CM_HINTSHOW'; Method: 'CMHintShow'; RecordType: 'TCMHintShow'),
    (Name: 'CM_STYLECHANGED'; Method: 'CMStyleChanged'; RecordType: 'TMessage'),
    (Name: 'CN_COMMAND'; Method: 'CNCommand'; RecordType: 'TWMCommand'),
    (Name: 'CN_NOTIFY'; Method: 'CNNotify'; RecordType: 'TWMNotify'),
    (Name: 'CN_KEYDOWN'; Method: 'CNKeyDown'; RecordType: 'TWMKeyDown'));

function MessageMethodName(const AMessage: string): string;
var
  Entry: TMessageEntry;
  Parts: TArray<string>;
  Index: Integer;
begin
  for Entry in MessageTable do
    if SameText(Entry.Name, Trim(AMessage)) then
      Exit(Entry.Method);
  // Unbekannte Botschaft: Präfix groß, jeder weitere Teil mit großem Anfangsbuchstaben.
  Parts := UpperCase(Trim(AMessage)).Split(['_']);
  if Length(Parts) = 0 then
    Exit('');
  Result := Parts[0];
  for Index := 1 to High(Parts) do
    if Parts[Index] <> '' then
      Result := Result + Parts[Index][1] + LowerCase(Copy(Parts[Index], 2, MaxInt));
end;

function MessageRecord(const AMessage: string): string;
var
  Entry: TMessageEntry;
begin
  for Entry in MessageTable do
    if SameText(Entry.Name, Trim(AMessage)) then
      Exit(Entry.RecordType);
  Result := 'TMessage';
end;

function RoutineSignature(const ADeclaration: string): string;
var
  Index, Depth: Integer;
  Text: string;
begin
  Text := StringReplace(StringReplace(ADeclaration, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  Depth := 0;
  for Index := 1 to Length(Text) do
    case Text[Index] of
      '(': Inc(Depth);
      ')': Dec(Depth);
      ';':
        if Depth = 0 then
        begin
          Text := Copy(Text, 1, Index - 1);
          Break;
        end;
    end;
  // Zeilenumbrüche und Einrückung zu einem Leerzeichen.
  while Pos('  ', Text) > 0 do
    Text := StringReplace(Text, '  ', ' ', [rfReplaceAll]);
  Result := Trim(Text);
end;

function ParameterNames(const ASignature: string): string;
var
  Open, Close, Colon: Integer;
  Group, Names: string;
  Name: string;
begin
  Result := '';
  Open := Pos('(', ASignature);
  Close := LastDelimiter(')', ASignature);
  if (Open = 0) or (Close < Open) then
    Exit;
  for Group in Copy(ASignature, Open + 1, Close - Open - 1).Split([';']) do
  begin
    Colon := Pos(':', Group);
    if Colon > 0 then
      Names := Copy(Group, 1, Colon - 1)
    else
      Names := Group;
    Names := Trim(Names);
    // Modifizierer const, var, out, constref vor den Namen weglassen.
    if StartsText('const ', Names) or StartsText('var ', Names) or StartsText('out ', Names) or
      StartsText('constref ', Names) then
      Names := Trim(Copy(Names, Pos(' ', Names) + 1, MaxInt));
    for Name in Names.Split([',']) do
      if Trim(Name) <> '' then
      begin
        if Result <> '' then
          Result := Result + ', ';
        Result := Result + Trim(Name);
      end;
  end;
end;

/// <summary>Abschnitt mit Deklaration vor "end" der Klasse und Rumpf in der implementation.</summary>
function AddMethod(ASource: TCommandSource; const AClass: TIndexSymbol; const ASection, ADeclaration,
  ABody: string): TArray<TRuleEdit>;
var
  EndLine: Integer;
  Indent: string;
begin
  EndLine := AClass.Range.EndPos.Line;
  Indent := ASource.Indent(EndLine);
  Result := [ASource.BeforeLine(EndLine, Indent + ASection + ASource.LineBreak + Indent + '  ' + ADeclaration),
    ASource.AddBody(AClass.Name, ABody), ASource.RemoveCommand];
end;

function Lines(ASource: TCommandSource; const AParts: array of string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AParts) do
  begin
    if Index > 0 then
      Result := Result + ASource.LineBreak;
    Result := Result + AParts[Index];
  end;
end;

{ /impl }

function ExecuteImpl(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Action: TCodeAction;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/impl gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    if not TClassCompletion.MissingBodies(Source.Tree, Source.Text,
      TTextPosition.Create(ClassSymbol.SelectionRange.StartPos.Line, 0), Action) then
      Exit(Fail('Alle Methoden von ' + ClassSymbol.Name + ' haben einen Rumpf', AReason));
    AEdits := Action.Edits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /ctor }

function ExecuteCtor(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Symbol: TIndexSymbol;
  Parameters, Assignments, Declaration, Body, Parameter, Name: string;
  Chosen: TArray<string>;
  Found: Boolean;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/ctor gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    if SameText(AContext.Arguments, 'owner') then
    begin
      Declaration := 'constructor Create(AOwner: TComponent); override;';
      Body := Lines(Source, [Format('constructor %s.Create(AOwner: TComponent);', [ClassSymbol.Name]), 'begin',
        '  inherited Create(AOwner);', 'end;']);
    end
    else
    begin
      // Ohne Argument alle Felder, sonst nur die genannten (mit oder ohne F).
      Chosen := nil;
      for Name in AContext.Arguments.Split([',', ' ', ';']) do
      begin
        if Name = '' then
          Continue;
        Found := False;
        for Symbol in Source.UnitIndex.Symbols do
          if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, ClassSymbol.Name) and
            (Symbol.TypeName <> '') and (SameText(Symbol.Name, Name) or SameText(Symbol.Name, 'F' + Name)) then
          begin
            Chosen := Chosen + [Symbol.Name];
            Found := True;
          end;
        if not Found then
          Exit(Fail(Format('Erwartet wird /ctor, /ctor owner oder /ctor FeldA, FeldB; kein Feld %s in %s',
            [Name, ClassSymbol.Name]), AReason));
      end;
      Parameters := '';
      Assignments := '';
      for Symbol in Source.UnitIndex.Symbols do
        if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, ClassSymbol.Name) and
          (Symbol.TypeName <> '') and ((Chosen = nil) or MatchText(Symbol.Name, Chosen)) then
        begin
          Parameter := 'A' + IfThen(StartsText('F', Symbol.Name) and (Length(Symbol.Name) > 1),
            Copy(Symbol.Name, 2, MaxInt), Symbol.Name);
          if Parameters <> '' then
            Parameters := Parameters + '; ';
          Parameters := Parameters + Format('const %s: %s', [Parameter, Symbol.TypeName]);
          Assignments := Assignments + Source.LineBreak + Format('  %s := %s;', [Symbol.Name, Parameter]);
        end;
      if Parameters <> '' then
        Parameters := '(' + Parameters + ')';
      Declaration := Format('constructor Create%s;', [Parameters]);
      Body := Format('constructor %s.Create%s;', [ClassSymbol.Name, Parameters]) + Source.LineBreak + 'begin' +
        Source.LineBreak + '  inherited Create;' + Assignments + Source.LineBreak + 'end;';
    end;
    AEdits := AddMethod(Source, ClassSymbol, 'public', Declaration, Body);
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /dtor }

function ExecuteDtor(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Fields: TArray<string>;
  Body: string;
  Index: Integer;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/dtor gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    Fields := CreatedFields(Source, ClassSymbol.Name);
    Body := Format('destructor %s.Destroy;', [ClassSymbol.Name]) + Source.LineBreak + 'begin';
    // In umgekehrter Reihenfolge der Erzeugung freigeben.
    for Index := High(Fields) downto 0 do
      Body := Body + Source.LineBreak + Format('  FreeAndNil(%s);', [Fields[Index]]);
    Body := Body + Source.LineBreak + '  inherited;' + Source.LineBreak + 'end;';
    AEdits := AddMethod(Source, ClassSymbol, 'public', 'destructor Destroy; override;', Body);
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /msg }

function ExecuteMsg(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Message, Name, RecordType: string;
begin
  AEdits := nil;
  Message := UpperCase(Trim(AContext.Arguments));
  if (Pos('_', Message) < 2) or not IsValidIdent(Message) then
    Exit(Fail('Erwartet wird /msg WM_NAME', AReason));
  Name := MessageMethodName(Message);
  RecordType := MessageRecord(Message);
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/msg gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    AEdits := AddMethod(Source, ClassSymbol, 'protected',
      Format('procedure %s(var Message: %s); message %s;', [Name, RecordType, Message]),
      Lines(Source, [Format('procedure %s.%s(var Message: %s);', [ClassSymbol.Name, Name, RecordType]), 'begin',
        '  inherited;', 'end;']));
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /override }

const
  VisibilityNames: array[TIndexVisibility] of string = ('public', 'published', 'protected', 'strict protected',
    'private', 'strict private');

/// <summary>Sucht eine virtuelle Methode AName in AUnit, Klasse AClassName; liefert auch den Vorfahren.</summary>
function FindInUnit(const AUnit: TUnitIndex; const AClassName, AName: string; out AMethod: TIndexSymbol;
  out AAncestor: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  AAncestor := '';
  Result := False;
  for Symbol in AUnit.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, AClassName) and
      (Length(Symbol.Ancestors) > 0) then
      AAncestor := Symbol.Ancestors[0];
  for Symbol in AUnit.Symbols do
    if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and Symbol.IsVirtual and
      SameText(Symbol.Container, AClassName) and SameText(Symbol.Name, AName) then
    begin
      AMethod := Symbol;
      Exit(True);
    end;
end;

/// <summary>Datei einer anderen Unit; der Index kennt keine Parameterlisten.</summary>
function LoadText(const AFileName: string; out AText: string): Boolean;
var
  Format: TFileFormat;
begin
  try
    AText := TFileEncoding.LoadFromFile(AFileName, Format);
    Result := True;
  except
    on EInOutError do
      Result := False;
    on EFOpenError do
      Result := False;
  end;
end;

function RangeText(const ALines: TArray<string>; const ARange: TTextRange): string;
var
  Index: Integer;
begin
  if ARange.StartPos.Line = ARange.EndPos.Line then
    Exit(Copy(ALines[ARange.StartPos.Line], ARange.StartPos.Character + 1,
      ARange.EndPos.Character - ARange.StartPos.Character));
  Result := Copy(ALines[ARange.StartPos.Line], ARange.StartPos.Character + 1, MaxInt);
  for Index := ARange.StartPos.Line + 1 to ARange.EndPos.Line - 1 do
    Result := Result + ' ' + ALines[Index];
  Result := Result + ' ' + Copy(ALines[ARange.EndPos.Line], 1, ARange.EndPos.Character);
end;

/// <summary>Kopf der virtuellen Methode AName im ersten Vorfahren, der sie hat (Datei, dann Index).</summary>
function FindVirtual(ASource: TCommandSource; const AIndex: ISymbolIndex; const AClass: TIndexSymbol;
  const AName: string; out ASignature: string; out AVisibility: TIndexVisibility): Boolean;
var
  ClassName, Ancestor, Text: string;
  Method: TIndexSymbol;
  Location: TSymbolLocation;
  UnitIndex: TUnitIndex;
  Depth: Integer;
  Found: Boolean;
begin
  Result := False;
  if Length(AClass.Ancestors) = 0 then
    Exit;
  ClassName := AClass.Ancestors[0];
  for Depth := 1 to 32 do
  begin
    if FindInUnit(ASource.UnitIndex, ClassName, AName, Method, Ancestor) then
    begin
      ASignature := RoutineSignature(RangeText(ASource.Lines, Method.Range));
      AVisibility := Method.Visibility;
      Exit(True);
    end;
    if Ancestor = '' then
    begin
      // Klasse aus einer anderen Unit über den Index.
      if AIndex = nil then
        Exit;
      Found := False;
      for Location in AIndex.FindSymbols(ClassName) do
        if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and AIndex.FindFile(Location.FileName, UnitIndex) then
        begin
          Found := True;
          Break;
        end;
      if not Found then
        Exit;
      if FindInUnit(UnitIndex, ClassName, AName, Method, Ancestor) then
      begin
        if not LoadText(UnitIndex.FileName, Text) then
          Exit;
        ASignature := RoutineSignature(RangeText(Text.Replace(#13#10, #10).Split([#10]), Method.Range));
        AVisibility := Method.Visibility;
        Exit(True);
      end;
    end;
    if Ancestor = '' then
      Exit;
    ClassName := Ancestor;
  end;
end;

function ExecuteOverride(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Signature, Keyword, Rest, Arguments, Call: string;
  Visibility: TIndexVisibility;
  Space: Integer;
begin
  AEdits := nil;
  if not IsValidIdent(AContext.Arguments) then
    Exit(Fail('Erwartet wird /override Methodenname', AReason));
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/override gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    if not FindVirtual(Source, AContext.Index, ClassSymbol, AContext.Arguments, Signature, Visibility) then
      Exit(Fail('Keine virtuelle Methode ' + AContext.Arguments + ' in den Vorfahren von ' + ClassSymbol.Name,
        AReason));
    // "procedure Paint" wird zu "procedure TFoo.Paint".
    Space := Pos(' ', Signature);
    Keyword := Copy(Signature, 1, Space - 1);
    Rest := Trim(Copy(Signature, Space + 1, MaxInt));
    if StartsText('class ', Signature) then
    begin
      Space := Pos(' ', Rest);
      Keyword := Keyword + ' ' + Copy(Rest, 1, Space - 1);
      Rest := Trim(Copy(Rest, Space + 1, MaxInt));
    end;
    Arguments := ParameterNames(Signature);
    if Arguments <> '' then
      Call := Format('inherited %s(%s)', [AContext.Arguments, Arguments])
    else
      Call := 'inherited ' + AContext.Arguments;
    if EndsText('function', Keyword) then
      Call := 'Result := ' + Call
    else if Arguments = '' then
      Call := 'inherited';
    AEdits := AddMethod(Source, ClassSymbol, VisibilityNames[Visibility], Signature + '; override;',
      Lines(Source, [Format('%s %s.%s;', [Keyword, ClassSymbol.Name, Rest]), 'begin', '  ' + Call + ';', 'end;']));
    Result := True;
  finally
    Source.Free;
  end;
end;

function CtorFields(const AContext: TSlashContext): TArray<string>;
var
  Source: TCommandSource;
  ClassSymbol, Symbol: TIndexSymbol;
begin
  Result := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit;
    for Symbol in Source.UnitIndex.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, ClassSymbol.Name) and
        (Symbol.TypeName <> '') then
        Result := Result + [Symbol.Name];
  finally
    Source.Free;
  end;
end;

/// <summary>Hängt die virtuellen Methoden von AClassName aus AUnit an AResult an, die weder in AOwn noch schon in
/// AResult stehen; AAncestor ist der erste Vorfahr von AClassName in AUnit ('' ohne).</summary>
procedure CollectVirtuals(const AUnit: TUnitIndex; const AClassName: string; const AOwn: TArray<string>;
  var AResult: TArray<string>; out AAncestor: string; out AFound: Boolean);
var
  Symbol: TIndexSymbol;
begin
  AAncestor := '';
  AFound := False;
  for Symbol in AUnit.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, AClassName) then
    begin
      AFound := True;
      if Length(Symbol.Ancestors) > 0 then
        AAncestor := Symbol.Ancestors[0];
    end;
  for Symbol in AUnit.Symbols do
    if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and Symbol.IsVirtual and
      SameText(Symbol.Container, AClassName) and not MatchText(Symbol.Name, AOwn) and
      not MatchText(Symbol.Name, AResult) then
      AResult := AResult + [Symbol.Name];
end;

function OverrideCandidates(const AContext: TSlashContext): TArray<string>;
var
  Source: TCommandSource;
  ClassSymbol, Symbol: TIndexSymbol;
  Own: TArray<string>;
  ClassName, Ancestor: string;
  Location: TSymbolLocation;
  UnitIndex: TUnitIndex;
  Depth: Integer;
  Found: Boolean;
begin
  Result := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) or (Length(ClassSymbol.Ancestors) = 0) then
      Exit;
    // Was die Klasse schon deklariert, steht nicht zur Wahl.
    Own := nil;
    for Symbol in Source.UnitIndex.Symbols do
      if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
        SameText(Symbol.Container, ClassSymbol.Name) then
        Own := Own + [Symbol.Name];
    ClassName := ClassSymbol.Ancestors[0];
    for Depth := 1 to 32 do
    begin
      CollectVirtuals(Source.UnitIndex, ClassName, Own, Result, Ancestor, Found);
      if not Found then
      begin
        // Klasse aus einer anderen Unit über den Index, wie bei /override.
        if AContext.Index = nil then
          Exit;
        for Location in AContext.Index.FindSymbols(ClassName) do
          if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and
            AContext.Index.FindFile(Location.FileName, UnitIndex) then
          begin
            CollectVirtuals(UnitIndex, ClassName, Own, Result, Ancestor, Found);
            Break;
          end;
      end;
      if Ancestor = '' then
        Exit;
      ClassName := Ancestor;
    end;
  finally
    Source.Free;
  end;
end;

function MessageNames: TArray<string>;
var
  Entry: TMessageEntry;
begin
  Result := nil;
  for Entry in MessageTable do
    Result := Result + [Entry.Name];
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterClassCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('impl', 'Fehlende Methodenrümpfe der Klasse anlegen', '/impl', ExecuteImpl));
  ARegistry.Register(Command('ctor', 'Konstruktor mit den Feldern als Parametern', '/ctor owner', ExecuteCtor));
  ARegistry.Register(Command('dtor', 'Destruktor, der erzeugte Felder freigibt', '/dtor', ExecuteDtor));
  ARegistry.Register(Command('override', 'Virtuelle Methode eines Vorfahren überschreiben', '/override Paint',
    ExecuteOverride));
  ARegistry.Register(Command('msg', 'Botschaftsmethode anlegen', '/msg WM_SIZE', ExecuteMsg));
end;

end.
