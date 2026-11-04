unit Atlas.Common.Editing.ClassCommands;

// Schnellbefehle für Klassen (#295) im Rahmen aus #293:
//   /impl            fehlende Methodenrümpfe der Klasse anlegen
//   /ctor [owner]    Konstruktor mit den Feldern als Parametern; "owner" für Komponenten;
//                    "/ctor FName, FAlter" nur mit diesen Feldern (Auswahl im Erzeugen-Menü, #719)
//   /dtor            Destruktor, der im Konstruktor erzeugte Felder freigibt; einen vorhandenen
//                    ergänzt er um die noch nicht freigegebenen
//   /override Name   virtuelle Methode eines Vorfahren überschreiben (auch aus dem Index)
//   /msg WM_SIZE     Botschaftsmethode mit passendem Record
//   /intf IFoo       IFoo an die Klasse hängen, Deklarationen und Rümpfe aller fehlenden
//                    Interface-Methoden anlegen (derselbe Erzeuger wie die Vervollständigung, #466)
//
// Deklarationen kommen in einen eigenen Abschnitt vor "end" der Klasse, Rümpfe
// hinter die letzte Methode der Klasse. Für die Auswahl im Erzeugen-Menü (#719)
// liefern CtorFields, OverrideCandidates und MessageNames die möglichen
// Argumente.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.Contract;

/// <summary>Trägt die Klassenbefehle über ARegister ein.</summary>
procedure RegisterClassCommands(const ARegister: TSlashRegister);

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
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Editing.InterfaceStubs,
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
  begin
    if SameText(Entry.Name, Trim(AMessage)) then
    begin
      Exit(Entry.Method);
    end;
  end;
  // Unbekannte Botschaft: Präfix groß, jeder weitere Teil mit großem Anfangsbuchstaben.
  Parts := UpperCase(Trim(AMessage)).Split(['_']);
  if Length(Parts) = 0 then
  begin
    Exit('');
  end;
  Result := Parts[0];
  for Index := 1 to High(Parts) do
  begin
    if Parts[Index] <> '' then
    begin
      Result := Result + Parts[Index][1] + LowerCase(Copy(Parts[Index], 2, MaxInt));
    end;
  end;
end;

function MessageRecord(const AMessage: string): string;
var
  Entry: TMessageEntry;
begin
  for Entry in MessageTable do
  begin
    if SameText(Entry.Name, Trim(AMessage)) then
    begin
      Exit(Entry.RecordType);
    end;
  end;
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
  begin
    Text := StringReplace(Text, '  ', ' ', [rfReplaceAll]);
  end;
  Result := Trim(Text);
end;

/// <summary>AList mit AItem dahinter, getrennt durch ASeparator, wenn AList nicht leer ist.</summary>
function AppendList(const AList, AItem, ASeparator: string): string;
begin
  Result := AItem;
  if AList <> '' then
  begin
    Result := AList + ASeparator + AItem;
  end;
end;

const
  /// <summary>Modifizierer vor den Namen einer Parametergruppe.</summary>
  cParameterModifiers: array[0..3] of string = ('const ', 'var ', 'out ', 'constref ');

/// <summary>Beginnt ANames mit einem Modifizierer (const, var, out, constref)?</summary>
function StartsWithModifier(const ANames: string): Boolean;
var
  mModifier: string;
begin
  Result := False;
  for mModifier in cParameterModifiers do
  begin
    Result := Result or StartsText(mModifier, ANames);
  end;
end;

/// <summary>Namen einer Parametergruppe ohne Typ und Modifizierer: "const A, B: Integer" wird "A, B".</summary>
function GroupNames(const AGroup: string): string;
var
  mColon: Integer;
begin
  Result := AGroup;
  mColon := Pos(':', Result);
  if mColon > 0 then
  begin
    Result := Copy(Result, 1, mColon - 1);
  end;
  Result := Trim(Result);
  if StartsWithModifier(Result) then
  begin
    Result := Trim(Copy(Result, Pos(' ', Result) + 1, MaxInt));
  end;
end;

function ParameterNames(const ASignature: string): string;
var
  mOpen, mClose: Integer;
  mGroup, mName: string;
begin
  Result := '';
  mOpen := Pos('(', ASignature);
  mClose := LastDelimiter(')', ASignature);
  if (mOpen = 0) or (mClose < mOpen) then
  begin
    Exit;
  end;
  for mGroup in Copy(ASignature, mOpen + 1, mClose - mOpen - 1).Split([';']) do
  begin
    for mName in GroupNames(mGroup).Split([',']) do
    begin
      if Trim(mName) <> '' then
      begin
        Result := AppendList(Result, Trim(mName), ', ');
      end;
    end;
  end;
end;

/// <summary>Abschnitt mit Deklaration vor "end" der Klasse und Rumpf in der implementation.</summary>
function AddMethod(ASource: TCommandSource; const AClass: TIndexSymbol; const ASection, ADeclaration,
  ABody: string): TArray<TTextEdit>;
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
    begin
      Result := Result + ASource.LineBreak;
    end;
    Result := Result + AParts[Index];
  end;
end;

{ /impl }

function ExecuteImpl(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Action: TCodeAction;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit(Fail('/impl gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    end;
    if not TClassCompletion.MissingBodies(Source.Tree, Source.Text,
      TTextPosition.Create(ClassSymbol.SelectionRange.StartPos.Line, 0), Action) then
    begin
      Exit(Fail('Alle Methoden von ' + ClassSymbol.Name + ' haben einen Rumpf', AReason));
    end;
    AEdits := Action.Edits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /ctor }

/// <summary>Feld der Klasse AClassName mit bekanntem Typ, das ein Konstruktor setzen kann?</summary>
function IsTypedField(const ASymbol: TIndexSymbol; const AClassName: string): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.Field) and SameText(ASymbol.Container, AClassName) and
    (ASymbol.TypeName <> '');
end;

/// <summary>Hängt die Felder von AClass namens AName oder F&lt;AName&gt; an AChosen an; False ohne.</summary>
function AddNamedFields(ASource: TCommandSource; const AClass: TIndexSymbol; const AName: string;
  var AChosen: TArray<string>): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := False;
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if IsTypedField(mSymbol, AClass.Name) and
      (SameText(mSymbol.Name, AName) or SameText(mSymbol.Name, 'F' + AName)) then
    begin
      AChosen := AChosen + [mSymbol.Name];
      Result := True;
    end;
  end;
end;

/// <summary>Die in AArguments genannten Felder (mit oder ohne F); ohne Argument nil für alle Felder. False mit
/// AUnknown, wenn ein Name kein Feld ist.</summary>
function ChosenFields(ASource: TCommandSource; const AClass: TIndexSymbol; const AArguments: string;
  out AChosen: TArray<string>; out AUnknown: string): Boolean;
var
  mName: string;
begin
  AChosen := nil;
  AUnknown := '';
  for mName in AArguments.Split([',', ' ', ';']) do
  begin
    if (mName <> '') and not AddNamedFields(ASource, AClass, mName, AChosen) then
    begin
      AUnknown := mName;
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Konstruktor, der die Felder AChosen (nil: alle) aus gleichnamigen Parametern setzt.</summary>
procedure FieldConstructor(ASource: TCommandSource; const AClass: TIndexSymbol; const AChosen: TArray<string>;
  out ADeclaration, ABody: string);
var
  mSymbol: TIndexSymbol;
  mParameters, mAssignments, mParameter: string;
begin
  mParameters := '';
  mAssignments := '';
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if IsTypedField(mSymbol, AClass.Name) and ((AChosen = nil) or MatchText(mSymbol.Name, AChosen)) then
    begin
      mParameter := 'A' + IfThen(StartsText('F', mSymbol.Name) and (Length(mSymbol.Name) > 1),
        Copy(mSymbol.Name, 2, MaxInt), mSymbol.Name);
      mParameters := AppendList(mParameters, Format('const %s: %s', [mParameter, mSymbol.TypeName]), '; ');
      mAssignments := mAssignments + ASource.LineBreak + Format('  %s := %s;', [mSymbol.Name, mParameter]);
    end;
  end;
  if mParameters <> '' then
  begin
    mParameters := '(' + mParameters + ')';
  end;
  ADeclaration := Format('constructor Create%s;', [mParameters]);
  ABody := Format('constructor %s.Create%s;', [AClass.Name, mParameters]) + ASource.LineBreak + 'begin' +
    ASource.LineBreak + '  inherited Create;' + mAssignments + ASource.LineBreak + 'end;';
end;

function ExecuteCtor(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClass: TIndexSymbol;
  mDeclaration, mBody, mUnknown: string;
  mChosen: TArray<string>;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClass) then
    begin
      Exit(Fail('/ctor gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    end;
    if SameText(AContext.Arguments, 'owner') then
    begin
      mDeclaration := 'constructor Create(AOwner: TComponent); override;';
      mBody := Lines(mSource, [Format('constructor %s.Create(AOwner: TComponent);', [mClass.Name]), 'begin',
        '  inherited Create(AOwner);', 'end;']);
    end
    else
    begin
      // Ohne Argument alle Felder, sonst nur die genannten (mit oder ohne F).
      if not ChosenFields(mSource, mClass, AContext.Arguments, mChosen, mUnknown) then
      begin
        Exit(Fail(Format('Erwartet wird /ctor, /ctor owner oder /ctor FeldA, FeldB; kein Feld %s in %s',
          [mUnknown, mClass.Name]), AReason));
      end;
      FieldConstructor(mSource, mClass, mChosen, mDeclaration, mBody);
    end;
    AEdits := AddMethod(mSource, mClass, 'public', mDeclaration, mBody);
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /dtor }

/// <summary>Freigabe von AField in der Zeile: FreeAndNil(F), F.Free oder F.DisposeOf.</summary>
function FreesField(const ALine, AField: string): Boolean;
var
  Line: string;
begin
  Line := LowerCase(StringReplace(ALine, ' ', '', [rfReplaceAll]));
  Result := (Pos('freeandnil(' + LowerCase(AField) + ')', Line) > 0) or
    (Pos(LowerCase(AField) + '.free', Line) > 0) or (Pos(LowerCase(AField) + '.disposeof', Line) > 0);
end;

/// <summary>Vorhandener Destruktor Destroy der Klasse: Rumpf ABody (mehrzeilig) und ob die Klasse ihn deklariert.</summary>
function FindDestructor(ASource: TCommandSource; const AClass: TIndexSymbol; out ABody: TIndexSymbol;
  out ADeclared: Boolean): Boolean;
var
  Symbol: TIndexSymbol;
begin
  ABody := Default(TIndexSymbol);
  ADeclared := False;
  Result := False;
  for Symbol in ASource.UnitIndex.Symbols do
  begin
    if (Symbol.Kind = TIndexSymbolKind.Constructor_) and SameText(Symbol.Container, AClass.Name) and
      SameText(Symbol.Name, 'Destroy') then
    begin
      if (Symbol.Range.StartPos.Line > AClass.Range.StartPos.Line) and
        (Symbol.Range.EndPos.Line < AClass.Range.EndPos.Line) then
      begin
        ADeclared := True;
      end
      else if Symbol.Range.EndPos.Line > Symbol.Range.StartPos.Line then
      begin
        ABody := Symbol;
        Result := True;
      end;
    end;
  end;
end;

/// <summary>Gibt der Rumpf ABody das Feld AField frei?</summary>
function FreedIn(ASource: TCommandSource; const ABody: TIndexSymbol; const AField: string): Boolean;
var
  mLine: Integer;
begin
  for mLine := ABody.Range.StartPos.Line to ABody.Range.EndPos.Line do
  begin
    if FreesField(ASource.Lines[mLine], AField) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Zeile, vor die die Freigaben kommen: das erste "inherited" im Rumpf, sonst das abschließende "end".</summary>
function FreeTarget(ASource: TCommandSource; const ABody: TIndexSymbol): Integer;
var
  mLine: Integer;
begin
  Result := ABody.Range.EndPos.Line;
  for mLine := ABody.Range.EndPos.Line downto ABody.Range.StartPos.Line do
  begin
    if StartsText('inherited', Trim(ASource.Lines[mLine])) then
    begin
      Result := mLine;
    end;
  end;
end;

/// <summary>Ergänzt den vorhandenen Rumpf ABody um die Freigabe von AFields vor "inherited" bzw. vor "end".</summary>
function ExtendDestructor(ASource: TCommandSource; const AClass, ABody: TIndexSymbol; const AFields: TArray<string>;
  out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mMissing: TArray<string>;
  mField, mText, mIndent: string;
  mTarget, mIndex: Integer;
begin
  mMissing := nil;
  for mField in AFields do
  begin
    if not FreedIn(ASource, ABody, mField) then
    begin
      mMissing := mMissing + [mField];
    end;
  end;
  if Length(mMissing) = 0 then
  begin
    Exit(Fail(Format('%s.Destroy gibt schon alle im Konstruktor erzeugten Felder frei', [AClass.Name]), AReason));
  end;
  mTarget := FreeTarget(ASource, ABody);
  mIndent := ASource.Indent(mTarget);
  if mTarget = ABody.Range.EndPos.Line then
  begin
    mIndent := mIndent + '  ';
  end;
  mText := '';
  // In umgekehrter Reihenfolge der Erzeugung freigeben.
  for mIndex := High(mMissing) downto 0 do
  begin
    mText := AppendList(mText, mIndent + Format('FreeAndNil(%s);', [mMissing[mIndex]]), ASource.LineBreak);
  end;
  AEdits := [ASource.BeforeLine(mTarget, mText), ASource.RemoveCommand];
  Result := True;
end;

function ExecuteDtor(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Existing: TIndexSymbol;
  Fields: TArray<string>;
  Body: string;
  Index: Integer;
  Declared: Boolean;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit(Fail('/dtor gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    end;
    Fields := CreatedFields(Source, ClassSymbol.Name);
    // Vorhandenen Destruktor ergänzen statt einen zweiten anzulegen.
    if FindDestructor(Source, ClassSymbol, Existing, Declared) then
    begin
      Exit(ExtendDestructor(Source, ClassSymbol, Existing, Fields, AEdits, AReason));
    end;
    Body := Format('destructor %s.Destroy;', [ClassSymbol.Name]) + Source.LineBreak + 'begin';
    // In umgekehrter Reihenfolge der Erzeugung freigeben.
    for Index := High(Fields) downto 0 do
    begin
      Body := Body + Source.LineBreak + Format('  FreeAndNil(%s);', [Fields[Index]]);
    end;
    Body := Body + Source.LineBreak + '  inherited;' + Source.LineBreak + 'end;';
    if Declared then
    begin
      AEdits := [Source.AddBody(ClassSymbol.Name, Body), Source.RemoveCommand];
    end
    else
    begin
      AEdits := AddMethod(Source, ClassSymbol, 'public', 'destructor Destroy; override;', Body);
    end;
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /msg }

function ExecuteMsg(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Message, Name, RecordType: string;
begin
  AEdits := nil;
  Message := UpperCase(Trim(AContext.Arguments));
  if (Pos('_', Message) < 2) or not IsValidIdent(Message) then
  begin
    Exit(Fail('Erwartet wird /msg WM_NAME', AReason));
  end;
  Name := MessageMethodName(Message);
  RecordType := MessageRecord(Message);
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit(Fail('/msg gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    end;
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
  begin
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, AClassName) and
      (Length(Symbol.Ancestors) > 0) then
    begin
      AAncestor := Symbol.Ancestors[0];
    end;
  end;
  for Symbol in AUnit.Symbols do
  begin
    if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and Symbol.IsVirtual and
      SameText(Symbol.Container, AClassName) and SameText(Symbol.Name, AName) then
    begin
      AMethod := Symbol;
      Exit(True);
    end;
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
  begin
    Exit(Copy(ALines[ARange.StartPos.Line], ARange.StartPos.Character + 1,
      ARange.EndPos.Character - ARange.StartPos.Character));
  end;
  Result := Copy(ALines[ARange.StartPos.Line], ARange.StartPos.Character + 1, MaxInt);
  for Index := ARange.StartPos.Line + 1 to ARange.EndPos.Line - 1 do
  begin
    Result := Result + ' ' + ALines[Index];
  end;
  Result := Result + ' ' + Copy(ALines[ARange.EndPos.Line], 1, ARange.EndPos.Character);
end;

/// <summary>Unit der Klasse AClassName aus einer anderen Unit über den Index; False ohne.</summary>
function FindClassUnit(const AIndex: ISymbolIndex; const AClassName: string; out AUnit: TUnitIndex): Boolean;
var
  mLocation: TSymbolLocation;
begin
  AUnit := Default(TUnitIndex);
  if AIndex <> nil then
  begin
    for mLocation in AIndex.FindSymbols(AClassName) do
    begin
      if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and AIndex.FindFile(mLocation.FileName, AUnit) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

type
  /// <summary>Kopf und Sichtbarkeit einer virtuellen Methode im Vorfahren.</summary>
  TVirtualHeader = record
    Signature: string;
    Visibility: TIndexVisibility;
  end;

function HeaderOf(const ALines: TArray<string>; const AMethod: TIndexSymbol): TVirtualHeader;
begin
  Result.Signature := RoutineSignature(RangeText(ALines, AMethod.Range));
  Result.Visibility := AMethod.Visibility;
end;

/// <summary>Sucht AName in der Klasse AClassName (Datei, dann Index); AAncestor ist der Vorfahr für die nächste
/// Stufe ('' beendet die Suche).</summary>
function FindVirtualIn(ASource: TCommandSource; const AIndex: ISymbolIndex; const AClassName, AName: string;
  out AHeader: TVirtualHeader; out AAncestor: string): Boolean;
var
  mMethod: TIndexSymbol;
  mUnit: TUnitIndex;
  mText: string;
begin
  AHeader := Default(TVirtualHeader);
  if FindInUnit(ASource.UnitIndex, AClassName, AName, mMethod, AAncestor) then
  begin
    AHeader := HeaderOf(ASource.Lines, mMethod);
    Exit(True);
  end;
  Result := False;
  // Klasse aus einer anderen Unit über den Index.
  if (AAncestor = '') and FindClassUnit(AIndex, AClassName, mUnit) and
    FindInUnit(mUnit, AClassName, AName, mMethod, AAncestor) then
  begin
    Result := LoadText(mUnit.FileName, mText);
    AAncestor := '';
    if Result then
    begin
      AHeader := HeaderOf(mText.Replace(#13#10, #10).Split([#10]), mMethod);
    end;
  end;
end;

/// <summary>Kopf der virtuellen Methode AName im ersten Vorfahren, der sie hat (Datei, dann Index).</summary>
function FindVirtual(ASource: TCommandSource; const AIndex: ISymbolIndex; const AClass: TIndexSymbol;
  const AName: string; out AHeader: TVirtualHeader): Boolean;
var
  mClassName, mAncestor: string;
  mDepth: Integer;
begin
  AHeader := Default(TVirtualHeader);
  Result := False;
  mClassName := '';
  if Length(AClass.Ancestors) > 0 then
  begin
    mClassName := AClass.Ancestors[0];
  end;
  mDepth := 0;
  while not Result and (mClassName <> '') and (mDepth < 32) do
  begin
    Result := FindVirtualIn(ASource, AIndex, mClassName, AName, AHeader, mAncestor);
    mClassName := mAncestor;
    Inc(mDepth);
  end;
end;

function ExecuteOverride(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Signature, Keyword, Rest, Arguments, Call: string;
  Header: TVirtualHeader;
  Space: Integer;
begin
  AEdits := nil;
  if not IsValidIdent(AContext.Arguments) then
  begin
    Exit(Fail('Erwartet wird /override Methodenname', AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit(Fail('/override gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    end;
    if not FindVirtual(Source, AContext.Index, ClassSymbol, AContext.Arguments, Header) then
    begin
      Exit(Fail('Keine virtuelle Methode ' + AContext.Arguments + ' in den Vorfahren von ' + ClassSymbol.Name,
        AReason));
    end;
    Signature := Header.Signature;
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
    begin
      Call := Format('inherited %s(%s)', [AContext.Arguments, Arguments]);
    end
    else
    begin
      Call := 'inherited ' + AContext.Arguments;
    end;
    if EndsText('function', Keyword) then
    begin
      Call := 'Result := ' + Call;
    end
    else if Arguments = '' then
    begin
      Call := 'inherited';
    end;
    AEdits := AddMethod(Source, ClassSymbol, VisibilityNames[Header.Visibility], Signature + '; override;',
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
    begin
      Exit;
    end;
    for Symbol in Source.UnitIndex.Symbols do
    begin
      if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, ClassSymbol.Name) and
        (Symbol.TypeName <> '') then
      begin
        Result := Result + [Symbol.Name];
      end;
    end;
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
  begin
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, AClassName) then
    begin
      AFound := True;
      if Length(Symbol.Ancestors) > 0 then
      begin
        AAncestor := Symbol.Ancestors[0];
      end;
    end;
  end;
  for Symbol in AUnit.Symbols do
  begin
    if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and Symbol.IsVirtual and
      SameText(Symbol.Container, AClassName) and not MatchText(Symbol.Name, AOwn) and
      not MatchText(Symbol.Name, AResult) then
    begin
      AResult := AResult + [Symbol.Name];
    end;
  end;
end;

/// <summary>Methoden, die die Klasse AClassName in AUnit selbst deklariert.</summary>
function OwnMethods(const AUnit: TUnitIndex; const AClassName: string): TArray<string>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
      SameText(mSymbol.Container, AClassName) then
    begin
      Result := Result + [mSymbol.Name];
    end;
  end;
end;

/// <summary>Wie CollectVirtuals über die eigene Unit AUnit, sonst die Unit der Klasse aus dem Index (wie bei
/// /override).</summary>
procedure CollectVirtualsFrom(const AIndex: ISymbolIndex; const AUnit: TUnitIndex; const AClassName: string;
  const AOwn: TArray<string>; var AResult: TArray<string>; out AAncestor: string);
var
  mForeign: TUnitIndex;
  mFound: Boolean;
begin
  CollectVirtuals(AUnit, AClassName, AOwn, AResult, AAncestor, mFound);
  if not mFound and FindClassUnit(AIndex, AClassName, mForeign) then
  begin
    CollectVirtuals(mForeign, AClassName, AOwn, AResult, AAncestor, mFound);
  end;
end;

function OverrideCandidates(const AContext: TSlashContext): TArray<string>;
var
  mSource: TCommandSource;
  mClass: TIndexSymbol;
  mOwn: TArray<string>;
  mClassName, mAncestor: string;
  mDepth: Integer;
begin
  Result := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClass) or (Length(mClass.Ancestors) = 0) then
    begin
      Exit;
    end;
    // Was die Klasse schon deklariert, steht nicht zur Wahl.
    mOwn := OwnMethods(mSource.UnitIndex, mClass.Name);
    mClassName := mClass.Ancestors[0];
    mDepth := 0;
    while (mClassName <> '') and (mDepth < 32) do
    begin
      CollectVirtualsFrom(AContext.Index, mSource.UnitIndex, mClassName, mOwn, Result, mAncestor);
      mClassName := mAncestor;
      Inc(mDepth);
    end;
  finally
    mSource.Free;
  end;
end;

function MessageNames: TArray<string>;
var
  Entry: TMessageEntry;
begin
  Result := nil;
  for Entry in MessageTable do
  begin
    Result := Result + [Entry.Name];
  end;
end;

{ /intf }

/// <summary>Schlüssel einer fehlenden Methode zum Vergleich zweier Listen.</summary>
function MemberKey(const AMember: TResolvedSymbol): string;
begin
  Result := LowerCase(AMember.Container + '.' + AMember.Name + '(' + string.Join(',', AMember.ParamTypes) + ')');
end;

/// <summary>Name ohne Typargumente: IComparer&lt;TKunde&gt; wird IComparer.</summary>
function PlainName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
end;

/// <summary>Token "class" im Kopf der Klasse AClass; -1 ohne.</summary>
function ClassKeywordToken(const ATokens: TArray<TPascalToken>; const AClass: TIndexSymbol): Integer;
begin
  Result := 0;
  while (Result <= High(ATokens)) and ((ATokens[Result].StartPos.Line < AClass.Range.StartPos.Line) or
    not ATokens[Result].IsKeyword('class')) do
  begin
    Inc(Result);
  end;
  if (Result > High(ATokens)) or (ATokens[Result].StartPos.Line > AClass.Range.EndPos.Line) then
  begin
    Result := -1;
  end;
end;

/// <summary>Schließende Klammer zur öffnenden an AOpen; -1 ohne.</summary>
function ClosingParen(const ATokens: TArray<TPascalToken>; AOpen: Integer): Integer;
var
  mDepth, mIndex: Integer;
begin
  mDepth := 0;
  for mIndex := AOpen to High(ATokens) do
  begin
    if ATokens[mIndex].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if ATokens[mIndex].IsSymbol(')') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := -1;
end;

/// <summary>Änderung am Kopf der Klasse: ", AName" vor die schließende Klammer der Vorfahrenliste, ohne Liste
/// "(TInterfacedObject, AName)" hinter "class".</summary>
function HeaderEdit(ASource: TCommandSource; const AClass: TIndexSymbol; const AName: string;
  out AEdit: TTextEdit): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mClose: Integer;
begin
  AEdit := Default(TTextEdit);
  mTokens := ASource.Tree.Tokens;
  mIndex := ClassKeywordToken(mTokens, AClass);
  Result := mIndex >= 0;
  if not Result then
  begin
    Exit;
  end;
  // class sealed / class abstract
  while (mIndex < High(mTokens)) and (SameText(mTokens[mIndex + 1].Text, 'sealed') or
    SameText(mTokens[mIndex + 1].Text, 'abstract')) do
  begin
    Inc(mIndex);
  end;
  if (mIndex < High(mTokens)) and mTokens[mIndex + 1].IsSymbol('(') then
  begin
    mClose := ClosingParen(mTokens, mIndex + 1);
    Result := mClose >= 0;
    if Result then
    begin
      AEdit := TTextEdit.Create(TTextRange.Create(mTokens[mClose].StartPos, mTokens[mClose].StartPos), ', ' + AName);
    end;
  end
  else
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(mTokens[mIndex].EndPos, mTokens[mIndex].EndPos),
      '(TInterfacedObject, ' + AName + ')');
  end;
end;

/// <summary>Vorfahren im Kopf der Klasse ohne AName ("TInterfacedObject", wenn der Kopf keine nennt); True, wenn
/// AName schon dort steht.</summary>
function ListedAncestors(ASource: TCommandSource; const AClass: TIndexSymbol; const AName: string;
  out ABefore: TArray<string>): Boolean;
var
  mHeader: TArray<string>;
  mText: string;
begin
  mHeader := TInterfaceStubs.HeaderAncestors(ASource.Lines, AClass.Range.StartPos.Line);
  Result := False;
  ABefore := nil;
  for mText in mHeader do
  begin
    if SameText(PlainName(mText), PlainName(AName)) then
    begin
      Result := True;
    end
    else
    begin
      ABefore := ABefore + [mText];
    end;
  end;
  if mHeader = nil then
  begin
    ABefore := ['TInterfacedObject'];
  end;
end;

function ContainsMember(const AMembers: TArray<TResolvedSymbol>; const AMember: TResolvedSymbol): Boolean;
var
  mItem: TResolvedSymbol;
begin
  for mItem in AMembers do
  begin
    if MemberKey(mItem) = MemberKey(AMember) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Methoden des Interfaces AName samt Vorfahren, die der Klasse ATypeName fehlen; was schon ohne AName
/// fehlt (Vorfahren ABefore), bleibt außen vor. False, wenn AName kein bekanntes Interface ist.</summary>
function MissingMembers(const AContext: TSlashContext; const AOwn: TUnitIndex; const ATypeName, AName: string;
  const ABefore: TArray<string>; out AMissing: TArray<TResolvedSymbol>): Boolean;
var
  mResolver: TNameResolver;
  mResolved, mMember: TResolvedSymbol;
  mKnown: TArray<TResolvedSymbol>;
begin
  AMissing := nil;
  mResolver := TNameResolver.Create(AContext.Index);
  try
    mResolver.Namespaces := AContext.Namespaces;
    Result := mResolver.ResolveNameFrom(AOwn, PlainName(AName), mResolved) and
      (mResolved.SymbolKind = TIndexSymbolKind.InterfaceType);
    if not Result then
    begin
      Exit;
    end;
    mKnown := mResolver.MissingInterfaceMembers(AOwn, ATypeName, ABefore);
    for mMember in mResolver.MissingInterfaceMembers(AOwn, ATypeName, ABefore + [AName]) do
    begin
      if not ContainsMember(mKnown, mMember) then
      begin
        AMissing := AMissing + [mMember];
      end;
    end;
  finally
    mResolver.Free;
  end;
end;

type
  /// <summary>Wohin /intf die Methoden schreibt.</summary>
  TIntfTarget = record
    Source: TCommandSource;
    TypeName: string;
    FileName: string;
    Section: string;
    EndLine: Integer;
    Indent: string;
    NeedHeader: Boolean;
  end;

/// <summary>Abschnitt für die Methoden nach slash.interfaceSection: private, protected oder public.</summary>
function InterfaceSection(const AContext: TSlashContext): string;
begin
  Result := '';
  if AContext.Host <> nil then
  begin
    Result := LowerCase(Trim(AContext.Host.Setting(AContext.Uri, TSlashSettings.InterfaceSection)));
  end;
  if (Result <> 'private') and (Result <> 'protected') then
  begin
    Result := 'public';
  end;
end;

function IntfTarget(ASource: TCommandSource; const AContext: TSlashContext; const AClass: TIndexSymbol): TIntfTarget;
begin
  Result.Source := ASource;
  Result.TypeName := AClass.QualifiedName;
  Result.FileName := '';
  if AContext.Uri <> '' then
  begin
    Result.FileName := TDocumentUris.ToPath(AContext.Uri);
  end;
  Result.Section := InterfaceSection(AContext);
  Result.EndLine := AClass.Range.EndPos.Line;
  Result.Indent := ASource.Indent(Result.EndLine);
  Result.NeedHeader := TInterfaceStubs.LastSection(ASource.Tree.Tokens, AClass.Range.StartPos.Line,
    Result.EndLine) <> Result.Section;
end;

/// <summary>Zeilen der Datei, in der AMember deklariert ist; False, wenn sie sich nicht lesen lässt.</summary>
function MemberLines(const ATarget: TIntfTarget; const AMember: TResolvedSymbol; out ALines: TArray<string>): Boolean;
var
  mText: string;
begin
  ALines := nil;
  Result := (AMember.FileName = '') or SameText(AMember.FileName, ATarget.FileName);
  if Result then
  begin
    ALines := ATarget.Source.Lines;
  end
  else if LoadText(AMember.FileName, mText) then
  begin
    ALines := mText.Replace(#13, '').Split([#10]);
    Result := True;
  end;
end;

/// <summary>Deklaration und Rumpf für die fehlende Methode AMember; nil, wenn sie sich nicht erzeugen lässt.</summary>
function MemberEdits(const ATarget: TIntfTarget; const AMember: TResolvedSymbol): TArray<TTextEdit>;
var
  mLines: TArray<string>;
  mStub: TInterfaceStub;
  mEdit: TTextEdit;
  mSource: TCommandSource;
begin
  Result := nil;
  mSource := ATarget.Source;
  if not MemberLines(ATarget, AMember, mLines) or not TInterfaceStubs.Make(TInterfaceStubs.GenericName(
    AMember.Container, AMember.Bindings), ATarget.TypeName, TInterfaceStubs.SubstituteWords(
    TInterfaceStubs.DeclarationOf(mLines, AMember.Range), AMember.Bindings), mSource.LineBreak, mStub) then
  begin
    Exit;
  end;
  Result := TInterfaceStubs.ClassEdits(mStub, ATarget.EndLine, ATarget.Indent, ATarget.Section, ATarget.NeedHeader,
    mSource.LineBreak);
  if TClassCompletion.BodyEdit(mSource.Tree, mSource.Text, ATarget.TypeName, mStub.Body, mEdit) then
  begin
    Result := Result + [mEdit];
  end
  else
  begin
    Result := Result + [mSource.AddBody(ATarget.TypeName, mStub.Body)];
  end;
end;

/// <summary>/intf AName in der Klasse am Befehl: fehlende Methoden und, wenn nötig, AName im Kopf.</summary>
function IntfEdits(ASource: TCommandSource; const AContext: TSlashContext; const AName: string;
  out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mClass: TIndexSymbol;
  mTarget: TIntfTarget;
  mOwn: TUnitIndex;
  mBefore: TArray<string>;
  mListed: Boolean;
  mMissing: TArray<TResolvedSymbol>;
  mMember: TResolvedSymbol;
  mEdits: TArray<TTextEdit>;
  mEdit: TTextEdit;
begin
  if not ASource.ClassAt(mClass) or (mClass.Range.StartPos.Line >= ASource.Line) or
    (mClass.Range.EndPos.Line <= ASource.Line) then
  begin
    Exit(Fail('/intf gilt nur in der Deklaration einer Klasse', AReason));
  end;
  mTarget := IntfTarget(ASource, AContext, mClass);
  mOwn := ASource.UnitIndex;
  mOwn.FileName := mTarget.FileName;
  mListed := ListedAncestors(ASource, mClass, AName, mBefore);
  if not MissingMembers(AContext, mOwn, mTarget.TypeName, AName, mBefore, mMissing) then
  begin
    Exit(Fail(Format('%s ist kein bekanntes Interface', [AName]), AReason));
  end;
  if mListed and (Length(mMissing) = 0) then
  begin
    Exit(Fail(Format('%s hängt schon an %s und ist vollständig implementiert', [AName, mClass.Name]), AReason));
  end;
  mEdits := nil;
  for mMember in mMissing do
  begin
    mEdits := mEdits + MemberEdits(mTarget, mMember);
  end;
  if not mListed and not HeaderEdit(ASource, mClass, AName, mEdit) then
  begin
    Exit(Fail(Format('Der Kopf von %s lässt sich nicht erweitern', [mClass.Name]), AReason));
  end;
  if not mListed then
  begin
    mEdits := [mEdit] + mEdits;
  end;
  AEdits := TInterfaceStubs.Merge(mEdits) + [ASource.RemoveCommand];
  Result := True;
end;

function ExecuteIntf(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mName: string;
begin
  AEdits := nil;
  mName := Trim(AContext.Arguments);
  if not IsValidIdent(PlainName(mName), True) then
  begin
    Exit(Fail('Erwartet wird /intf IName', AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    Result := IntfEdits(mSource, AContext, mName, AEdits, AReason);
  finally
    mSource.Free;
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterClassCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('impl', 'Fehlende Methodenrümpfe der Klasse anlegen', '/impl', ExecuteImpl));
  ARegister(Command('ctor', 'Konstruktor mit den Feldern als Parametern', '/ctor owner', ExecuteCtor));
  ARegister(Command('dtor', 'Destruktor, der erzeugte Felder freigibt', '/dtor', ExecuteDtor));
  ARegister(Command('override', 'Virtuelle Methode eines Vorfahren überschreiben', '/override Paint',
    ExecuteOverride));
  ARegister(Command('msg', 'Botschaftsmethode anlegen', '/msg WM_SIZE', ExecuteMsg));
  ARegister(Command('intf', 'Interface an die Klasse hängen und seine Methoden anlegen', '/intf IExporter',
    ExecuteIntf));
end;

end.
