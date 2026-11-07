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

/// <summary>Methodenname zur Botschaft: WM_SIZE wird zu WMSize, CM_MOUSEENTER zu CMMouseEnter (Tabelle, sonst je Teil
/// groß).</summary>
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
  Atlas.Common.Editing.ClassBodies,
  Atlas.Common.Editing.TypeComments,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TClassCommandsText = (ImplOnlyAppliesInA, AllMethodsOfHaveA, CtorOnlyAppliesInA, ExpectedIsCtorCtorOwner,
    DtorOnlyAppliesInA, ExpectedIsMsgWMNAME, MsgOnlyAppliesInA, ExpectedIsOverrideMethodName, OverrideOnlyAppliesInA,
    NoVirtualMethodInThe, IntfOnlyAppliesInThe, IsNotAKnownInterface, IsAlreadyAttachedToAnd, TheHeaderOfCannotBe,
    ExpectedIsIntfIName, CreateMissingMethodBodiesOf, ConstructorWithTheFieldsAs, DestructorThatFreesCreatedFields,
    OverrideAVirtualMethodOf, AttachAnInterfaceToThe, DestroyAlreadyFreesAllFields, CreateAMessageMethod);

const
  cTexts: array[TClassCommandsText] of TAtlasText = (
    (De: '/impl gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/impl only applies in a class or one of its methods'),
    (De: 'Alle Methoden von %s haben einen Rumpf'; En: 'All methods of %s have a body'),
    (De: '/ctor gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/ctor only applies in a class or one of its methods'),
    (De: 'Erwartet wird /ctor, /ctor owner oder /ctor FeldA, FeldB; kein Feld %s in %s';
     En: 'Expected is /ctor, /ctor owner or /ctor FieldA, FieldB; no field %s in %s'),
    (De: '/dtor gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/dtor only applies in a class or one of its methods'),
    (De: 'Erwartet wird /msg WM_NAME'; En: 'Expected is /msg WM_NAME'),
    (De: '/msg gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/msg only applies in a class or one of its methods'),
    (De: 'Erwartet wird /override Methodenname'; En: 'Expected is /override MethodName'),
    (De: '/override gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/override only applies in a class or one of its methods'),
    (De: 'Keine virtuelle Methode %s in den Vorfahren von '; En: 'No virtual method %s in the ancestors of '),
    (De: '/intf gilt nur in der Deklaration einer Klasse'; En: '/intf only applies in the declaration of a class'),
    (De: '%s ist kein bekanntes Interface'; En: '%s is not a known interface'),
    (De: '%s hängt schon an %s und ist vollständig implementiert';
     En: '%s is already attached to %s and fully implemented'),
    (De: 'Der Kopf von %s lässt sich nicht erweitern'; En: 'The header of %s cannot be extended'),
    (De: 'Erwartet wird /intf IName'; En: 'Expected is /intf IName'),
    (De: 'Fehlende Methodenrümpfe der Klasse anlegen'; En: 'Create missing method bodies of the class'),
    (De: 'Konstruktor mit den Feldern als Parametern'; En: 'Constructor with the fields as parameters'),
    (De: 'Destruktor, der erzeugte Felder freigibt'; En: 'Destructor that frees created fields'),
    (De: 'Virtuelle Methode eines Vorfahren überschreiben'; En: 'Override a virtual method of an ancestor'),
    (De: 'Interface an die Klasse hängen und seine Methoden anlegen';
     En: 'Attach an interface to the class and create its methods'),
    (De: '%s.Destroy gibt schon alle im Konstruktor erzeugten Felder frei';
     En: '%s.Destroy already frees all fields created in the constructor'),
    (De: 'Botschaftsmethode anlegen'; En: 'Create a message method'));

{$SCOPEDENUMS OFF}

type
  TMessageEntry = record
    Name: string;
    Method: string;
    RecordType: string;
  end;

const
  // Häufige Botschaften mit Methodennamen wie in der VCL und Record aus Winapi.Messages bzw. Vcl.Controls.
  cMessageTable: array[0..37] of TMessageEntry = (
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
  mEntry: TMessageEntry;
  mParts: TArray<string>;
  mIndex: Integer;
begin
  for mEntry in cMessageTable do
  begin
    if SameText(mEntry.Name, Trim(AMessage)) then
    begin
      Exit(mEntry.Method);
    end;
  end;
  // Unbekannte Botschaft: Präfix groß, jeder weitere Teil mit großem Anfangsbuchstaben.
  mParts := UpperCase(Trim(AMessage)).Split(['_']);
  if Length(mParts) = 0 then
  begin
    Exit('');
  end;
  Result := mParts[0];
  for mIndex := 1 to High(mParts) do
  begin
    if mParts[mIndex] <> '' then
    begin
      Result := Result + mParts[mIndex][1] + LowerCase(Copy(mParts[mIndex], 2, MaxInt));
    end;
  end;
end;

function MessageRecord(const AMessage: string): string;
var
  mEntry: TMessageEntry;
begin
  for mEntry in cMessageTable do
  begin
    if SameText(mEntry.Name, Trim(AMessage)) then
    begin
      Exit(mEntry.RecordType);
    end;
  end;
  Result := 'TMessage';
end;

function RoutineSignature(const ADeclaration: string): string;
var
  mIndex, mDepth: Integer;
  mText: string;
begin
  mText := StringReplace(StringReplace(ADeclaration, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  mDepth := 0;
  for mIndex := 1 to Length(mText) do
    case mText[mIndex] of
      '(': Inc(mDepth);
      ')': Dec(mDepth);
      ';':
        if mDepth = 0 then
        begin
          mText := Copy(mText, 1, mIndex - 1);
          Break;
        end;
    end;
  // Zeilenumbrüche und Einrückung zu einem Leerzeichen.
  while Pos('  ', mText) > 0 do
  begin
    mText := StringReplace(mText, '  ', ' ', [rfReplaceAll]);
  end;
  Result := Trim(mText);
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
  mEndLine: Integer;
  mIndent: string;
begin
  mEndLine := AClass.Range.EndPos.Line;
  mIndent := ASource.Indent(mEndLine);
  Result := [ASource.BeforeLine(mEndLine, mIndent + ASection + ASource.LineBreak + mIndent + '  ' + ADeclaration),
    ASource.AddBody(AClass.Name, ABody), ASource.RemoveCommand];
end;

function Lines(ASource: TCommandSource; const AParts: array of string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(AParts) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ASource.LineBreak;
    end;
    Result := Result + AParts[mIndex];
  end;
end;

{ /impl }

function ExecuteImpl(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClassSymbol: TIndexSymbol;
  mAction: TCodeAction;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClassSymbol) then
    begin
      Exit(Fail(cTexts[TClassCommandsText.ImplOnlyAppliesInA].Text, AReason));
    end;
    // Kommentar, Reihenfolge und Vorbefüllung nach classCompletion.* (#1834).
    if not TClassCompletion.MissingBodies(mSource.Tree, mSource.Text,
      TTextPosition.Create(mClassSymbol.SelectionRange.StartPos.Line, 0),
      TClassBodyOptions.FromHost(AContext.Host, AContext.Uri, AContext.Style), mAction) then
    begin
      Exit(Fail(cTexts[TClassCommandsText.AllMethodsOfHaveA].Fmt([mClassSymbol.Name]), AReason));
    end;
    AEdits := mAction.Edits + [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
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
      Exit(Fail(cTexts[TClassCommandsText.CtorOnlyAppliesInA].Text, AReason));
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
        Exit(Fail(cTexts[TClassCommandsText.ExpectedIsCtorCtorOwner].Fmt([mUnknown, mClass.Name]), AReason));
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
  mLine: string;
begin
  mLine := LowerCase(StringReplace(ALine, ' ', '', [rfReplaceAll]));
  Result := (Pos('freeandnil(' + LowerCase(AField) + ')', mLine) > 0) or
    (Pos(LowerCase(AField) + '.free', mLine) > 0) or (Pos(LowerCase(AField) + '.disposeof', mLine) > 0);
end;

/// <summary>Vorhandener Destruktor Destroy der Klasse: Rumpf ABody (mehrzeilig) und ob die Klasse ihn
/// deklariert.</summary>
function FindDestructor(ASource: TCommandSource; const AClass: TIndexSymbol; out ABody: TIndexSymbol;
  out ADeclared: Boolean): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  ABody := Default(TIndexSymbol);
  ADeclared := False;
  Result := False;
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Constructor_) and SameText(mSymbol.Container, AClass.Name) and
      SameText(mSymbol.Name, 'Destroy') then
    begin
      if (mSymbol.Range.StartPos.Line > AClass.Range.StartPos.Line) and
        (mSymbol.Range.EndPos.Line < AClass.Range.EndPos.Line) then
      begin
        ADeclared := True;
      end
      else if mSymbol.Range.EndPos.Line > mSymbol.Range.StartPos.Line then
      begin
        ABody := mSymbol;
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

/// <summary>Zeile, vor die die Freigaben kommen: das erste "inherited" im Rumpf, sonst das abschließende
/// "end".</summary>
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
    Exit(Fail(cTexts[TClassCommandsText.DestroyAlreadyFreesAllFields].Fmt([AClass.Name]), AReason));
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
  mSource: TCommandSource;
  mClassSymbol, mExisting: TIndexSymbol;
  mFields: TArray<string>;
  mBody: string;
  mIndex: Integer;
  mDeclared: Boolean;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClassSymbol) then
    begin
      Exit(Fail(cTexts[TClassCommandsText.DtorOnlyAppliesInA].Text, AReason));
    end;
    mFields := CreatedFields(mSource, mClassSymbol.Name);
    // Vorhandenen Destruktor ergänzen statt einen zweiten anzulegen.
    if FindDestructor(mSource, mClassSymbol, mExisting, mDeclared) then
    begin
      Exit(ExtendDestructor(mSource, mClassSymbol, mExisting, mFields, AEdits, AReason));
    end;
    mBody := Format('destructor %s.Destroy;', [mClassSymbol.Name]) + mSource.LineBreak + 'begin';
    // In umgekehrter Reihenfolge der Erzeugung freigeben.
    for mIndex := High(mFields) downto 0 do
    begin
      mBody := mBody + mSource.LineBreak + Format('  FreeAndNil(%s);', [mFields[mIndex]]);
    end;
    mBody := mBody + mSource.LineBreak + '  inherited;' + mSource.LineBreak + 'end;';
    if mDeclared then
    begin
      AEdits := [mSource.AddBody(mClassSymbol.Name, mBody), mSource.RemoveCommand];
    end
    else
    begin
      AEdits := AddMethod(mSource, mClassSymbol, 'public', 'destructor Destroy; override;', mBody);
    end;
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /msg }

function ExecuteMsg(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClassSymbol: TIndexSymbol;
  mMessage, mName, mRecordType: string;
begin
  AEdits := nil;
  mMessage := UpperCase(Trim(AContext.Arguments));
  if (Pos('_', mMessage) < 2) or not IsValidIdent(mMessage) then
  begin
    Exit(Fail(cTexts[TClassCommandsText.ExpectedIsMsgWMNAME].Text, AReason));
  end;
  mName := MessageMethodName(mMessage);
  mRecordType := MessageRecord(mMessage);
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClassSymbol) then
    begin
      Exit(Fail(cTexts[TClassCommandsText.MsgOnlyAppliesInA].Text, AReason));
    end;
    AEdits := AddMethod(mSource, mClassSymbol, 'protected',
      Format('procedure %s(var Message: %s); message %s;', [mName, mRecordType, mMessage]),
      Lines(mSource, [Format('procedure %s.%s(var Message: %s);', [mClassSymbol.Name, mName, mRecordType]), 'begin',
        '  inherited;', 'end;']));
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /override }

const
  cVisibilityNames: array[TIndexVisibility] of string = ('public', 'published', 'protected', 'strict protected',
    'private', 'strict private');

/// <summary>Sucht eine virtuelle Methode AName in AUnit, Klasse AClassName; liefert auch den Vorfahren.</summary>
function FindInUnit(const AUnit: TUnitIndex; const AClassName, AName: string; out AMethod: TIndexSymbol;
  out AAncestor: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  AAncestor := '';
  Result := False;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and SameText(mSymbol.Name, AClassName) and
      (Length(mSymbol.Ancestors) > 0) then
    begin
      AAncestor := mSymbol.Ancestors[0];
    end;
  end;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and mSymbol.IsVirtual and
      SameText(mSymbol.Container, AClassName) and SameText(mSymbol.Name, AName) then
    begin
      AMethod := mSymbol;
      Exit(True);
    end;
  end;
end;

/// <summary>Datei einer anderen Unit; der Index kennt keine Parameterlisten.</summary>
function LoadText(const AFileName: string; out AText: string): Boolean;
var
  mFormat: TFileFormat;
begin
  try
    AText := TFileEncoding.LoadFromFile(AFileName, mFormat);
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
  mIndex: Integer;
begin
  if ARange.StartPos.Line = ARange.EndPos.Line then
  begin
    Exit(Copy(ALines[ARange.StartPos.Line], ARange.StartPos.Character + 1,
      ARange.EndPos.Character - ARange.StartPos.Character));
  end;
  Result := Copy(ALines[ARange.StartPos.Line], ARange.StartPos.Character + 1, MaxInt);
  for mIndex := ARange.StartPos.Line + 1 to ARange.EndPos.Line - 1 do
  begin
    Result := Result + ' ' + ALines[mIndex];
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
  mSource: TCommandSource;
  mClassSymbol: TIndexSymbol;
  mSignature, mKeyword, mRest, mArguments, mCall: string;
  mHeader: TVirtualHeader;
  mSpace: Integer;
begin
  AEdits := nil;
  if not IsValidIdent(AContext.Arguments) then
  begin
    Exit(Fail(cTexts[TClassCommandsText.ExpectedIsOverrideMethodName].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClassSymbol) then
    begin
      Exit(Fail(cTexts[TClassCommandsText.OverrideOnlyAppliesInA].Text, AReason));
    end;
    if not FindVirtual(mSource, AContext.Index, mClassSymbol, AContext.Arguments, mHeader) then
    begin
      Exit(Fail(cTexts[TClassCommandsText.NoVirtualMethodInThe].Fmt([AContext.Arguments]) + mClassSymbol.Name,
        AReason));
    end;
    mSignature := mHeader.Signature;
    // "procedure Paint" wird zu "procedure TFoo.Paint".
    mSpace := Pos(' ', mSignature);
    mKeyword := Copy(mSignature, 1, mSpace - 1);
    mRest := Trim(Copy(mSignature, mSpace + 1, MaxInt));
    if StartsText('class ', mSignature) then
    begin
      mSpace := Pos(' ', mRest);
      mKeyword := mKeyword + ' ' + Copy(mRest, 1, mSpace - 1);
      mRest := Trim(Copy(mRest, mSpace + 1, MaxInt));
    end;
    mArguments := ParameterNames(mSignature);
    if mArguments <> '' then
    begin
      mCall := Format('inherited %s(%s)', [AContext.Arguments, mArguments]);
    end
    else
    begin
      mCall := 'inherited ' + AContext.Arguments;
    end;
    if EndsText('function', mKeyword) then
    begin
      mCall := 'Result := ' + mCall;
    end
    else if mArguments = '' then
    begin
      mCall := 'inherited';
    end;
    AEdits := AddMethod(mSource, mClassSymbol, cVisibilityNames[mHeader.Visibility], mSignature + '; override;',
      Lines(mSource, [Format('%s %s.%s;', [mKeyword, mClassSymbol.Name, mRest]), 'begin', '  ' + mCall + ';', 'end;']));
    Result := True;
  finally
    mSource.Free;
  end;
end;

function CtorFields(const AContext: TSlashContext): TArray<string>;
var
  mSource: TCommandSource;
  mClassSymbol, mSymbol: TIndexSymbol;
begin
  Result := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClassSymbol) then
    begin
      Exit;
    end;
    for mSymbol in mSource.UnitIndex.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, mClassSymbol.Name) and
        (mSymbol.TypeName <> '') then
      begin
        Result := Result + [mSymbol.Name];
      end;
    end;
  finally
    mSource.Free;
  end;
end;

/// <summary>Hängt die virtuellen Methoden von AClassName aus AUnit an AResult an, die weder in AOwn noch schon in
/// AResult stehen; AAncestor ist der erste Vorfahr von AClassName in AUnit ('' ohne).</summary>
procedure CollectVirtuals(const AUnit: TUnitIndex; const AClassName: string; const AOwn: TArray<string>;
  var AResult: TArray<string>; out AAncestor: string; out AFound: Boolean);
var
  mSymbol: TIndexSymbol;
begin
  AAncestor := '';
  AFound := False;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and SameText(mSymbol.Name, AClassName) then
    begin
      AFound := True;
      if Length(mSymbol.Ancestors) > 0 then
      begin
        AAncestor := mSymbol.Ancestors[0];
      end;
    end;
  end;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and mSymbol.IsVirtual and
      SameText(mSymbol.Container, AClassName) and not MatchText(mSymbol.Name, AOwn) and
      not MatchText(mSymbol.Name, AResult) then
    begin
      AResult := AResult + [mSymbol.Name];
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
  mEntry: TMessageEntry;
begin
  Result := nil;
  for mEntry in cMessageTable do
  begin
    Result := Result + [mEntry.Name];
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
    mKnown := mResolver.Queries.MissingInterfaceMembers(AOwn, ATypeName, ABefore);
    for mMember in mResolver.Queries.MissingInterfaceMembers(AOwn, ATypeName, ABefore + [AName]) do
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
    Result := LowerCase(Trim(AContext.Host.Setting(AContext.Uri, TSlashSettings.cInterfaceSection)));
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
function MemberEdits(const ATarget: TIntfTarget; const AMember: TResolvedSymbol;
  const AOptions: TClassBodyOptions): TArray<TTextEdit>;
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
  if TClassCompletion.BodyEdit(mSource.Tree, mSource.Text, ATarget.TypeName, mStub.Body, AOptions, mEdit) then
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
  mOptions: TClassBodyOptions;
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
    Exit(Fail(cTexts[TClassCommandsText.IntfOnlyAppliesInThe].Text, AReason));
  end;
  mTarget := IntfTarget(ASource, AContext, mClass);
  mOwn := ASource.UnitIndex;
  mOwn.FileName := mTarget.FileName;
  mListed := ListedAncestors(ASource, mClass, AName, mBefore);
  if not MissingMembers(AContext, mOwn, mTarget.TypeName, AName, mBefore, mMissing) then
  begin
    Exit(Fail(cTexts[TClassCommandsText.IsNotAKnownInterface].Fmt([AName]), AReason));
  end;
  if mListed and (Length(mMissing) = 0) then
  begin
    Exit(Fail(cTexts[TClassCommandsText.IsAlreadyAttachedToAnd].Fmt([AName, mClass.Name]), AReason));
  end;
  mEdits := nil;
  mOptions := TClassBodyOptions.Default;
  for mMember in mMissing do
  begin
    mEdits := mEdits + MemberEdits(mTarget, mMember, mOptions);
    // Jede Methode sieht denselben Ausgangstext: Den Typkommentar bekommt nur die erste.
    mOptions.TypeComment := TTypeCommentStyle.Off;
  end;
  if not mListed and not HeaderEdit(ASource, mClass, AName, mEdit) then
  begin
    Exit(Fail(cTexts[TClassCommandsText.TheHeaderOfCannotBe].Fmt([mClass.Name]), AReason));
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
    Exit(Fail(cTexts[TClassCommandsText.ExpectedIsIntfIName].Text, AReason));
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
  ARegister(Command('impl', cTexts[TClassCommandsText.CreateMissingMethodBodiesOf].Text, '/impl', ExecuteImpl));
  ARegister(Command('ctor', cTexts[TClassCommandsText.ConstructorWithTheFieldsAs].Text, '/ctor owner', ExecuteCtor));
  ARegister(Command('dtor', cTexts[TClassCommandsText.DestructorThatFreesCreatedFields].Text, '/dtor', ExecuteDtor));
  ARegister(Command('override', cTexts[TClassCommandsText.OverrideAVirtualMethodOf].Text, '/override Paint',
    ExecuteOverride));
  ARegister(Command('msg', cTexts[TClassCommandsText.CreateAMessageMethod].Text, '/msg WM_SIZE', ExecuteMsg));
  ARegister(Command('intf', cTexts[TClassCommandsText.AttachAnInterfaceToThe].Text, '/intf IExporter',
    ExecuteIntf));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.ClassCommands', cTexts);

end.
