unit Atlas.Common.Editing.InterfaceStubs;

// Fehlende Interface-Methoden einer Klasse anlegen (#466), ohne Namensauflösung. Gemeinsamer Erzeuger für die
// Vervollständigung (#466), die Code-Aktion „Interface-Methoden implementieren“ (#42) und den Schnellbefehl
// /intf (#295):
//   - Split: Kopf und Direktiven einer Methodendeklaration ("procedure Name(...): T; stdcall;").
//   - Make: Deklaration für die Klasse (mit overload und Aufrufkonvention) und Rumpf wie bei #443, aber ohne
//     inherited; Funktionen setzen Result auf Default(<Typ>).
//   - LastSection: letzter Sichtbarkeitsabschnitt der Klasse; ist er der gewünschte, braucht es keinen neuen.
//   - ClassEdits: Abschnitt, Kommentar "{ IExporter }" und Deklaration vor dem "end" der Klasse. Alle Einfügungen
//     eines Interfaces stehen an derselben Stelle; Merge fasst sie zu einer Änderung zusammen und lässt
//     doppelte Abschnitte und Kommentare weg.
//   - DeclarationOf, HeaderAncestors, SubstituteWords, GenericName: Deklarationstext, Vorfahrenliste aus dem
//     Quelltext und Typargumente generischer Interfaces, für Vervollständigung und /intf gleich.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  TInterfaceStub = record
    /// <summary>Deklarierendes Interface, z. B. "IExporter".</summary>
    InterfaceName: string;
    /// <summary>Name der Methode.</summary>
    Name: string;
    /// <summary>"procedure Export(const AFileName: string);" ohne Einrückung.</summary>
    Declaration: string;
    /// <summary>Rumpf "procedure TJsonExporter.Export(...);" bis "end;" mit ALineBreak, ohne Einrückung.</summary>
    Body: string;
  end;

  TInterfaceStubs = class
  public
    /// <summary>Kopf "Name(...): T" und Direktiven (klein, mit Leerzeichen umgeben, z. B. " virtual overload ")
    /// aus einer Methodendeklaration; AIsClass bei "class procedure". False ohne procedure bzw. function.</summary>
    class function Split(const ADeclaration: string; out AIsClass: Boolean; out AKind, AHead,
      ADirectives: string): Boolean; static;
    /// <summary>Ergebnistyp aus "Name(A: T): R" bzw. "Name: R"; '' bei Prozeduren.</summary>
    class function ReturnType(const AHead: string): string; static;
    /// <summary>Stub für eine Interface-Methode mit der Deklaration ADeclaration; False, wenn sie keine Methode
    /// ist.</summary>
    class function Make(const AInterfaceName, ATypeName, ADeclaration, ALineBreak: string;
      out AStub: TInterfaceStub): Boolean; static;
    /// <summary>Letzter Sichtbarkeitsabschnitt in einer Klassendeklaration zwischen den Zeilen AFirstLine und
    /// ALastLine (beide ausgeschlossen): "private", "strict protected", "public" ...; '' ohne.</summary>
    class function LastSection(const ATokens: TArray<TPascalToken>; AFirstLine, ALastLine: Integer): string; static;
    /// <summary>Einfügungen vor Zeile AEndLine (dem "end" der Klasse, eingerückt mit AIndent): mit AHeader der
    /// Abschnitt ASection, dann der Kommentar zum Interface und die Deklaration, eine Ebene tiefer.</summary>
    class function ClassEdits(const AStub: TInterfaceStub; AEndLine: Integer; const AIndent, ASection: string;
      AHeader: Boolean; const ALineBreak: string): TArray<TTextEdit>; static;
    /// <summary>Fasst Änderungen mit gleichem Bereich zusammen: Texte in der Reihenfolge des ersten Auftretens,
    /// gleiche Texte nur einmal. Bereiche bleiben in der Reihenfolge ihres ersten Auftretens.</summary>
    class function Merge(const AEdits: TArray<TTextEdit>): TArray<TTextEdit>; static;
    /// <summary>Deklaration von ARange; über mehr als MaxLines Zeilen (Klassen, Records) nur die erste.</summary>
    class function DeclarationOf(const ALines: TArray<string>; const ARange: TTextRange): string; static;
    /// <summary>Vorfahrenliste der Klasse ab Zeile AStartLine wie im Quelltext, samt Typargumenten
    /// ("TInterfacedObject", "IComparer&lt;TKunde&gt;"); nil, wenn kein "class(" folgt (#466).</summary>
    class function HeaderAncestors(const ALines: TArray<string>; AStartLine: Integer): TArray<string>; static;
    /// <summary>Setzt Bindungen "T=TKunde" wortweise in AText ein (#466).</summary>
    class function SubstituteWords(const AText: string; const ABindings: TArray<string>): string; static;
    /// <summary>"IComparer&lt;TKunde&gt;" aus Container und Bindungen; ohne Bindungen der Container.</summary>
    class function GenericName(const AContainer: string; const ABindings: TArray<string>): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.RegularExpressions;

class function TInterfaceStubs.Split(const ADeclaration: string; out AIsClass: Boolean; out AKind, AHead,
  ADirectives: string): Boolean;
var
  mText: string;
  mIndex, mDepth: Integer;
begin
  AKind := '';
  AHead := '';
  ADirectives := '';
  mText := Trim(ADeclaration);
  AIsClass := StartsText('class ', mText);
  if AIsClass then
  begin
    mText := TrimLeft(Copy(mText, 7, MaxInt));
  end;
  if StartsText('procedure ', mText) then
  begin
    AKind := 'procedure';
  end
  else if StartsText('function ', mText) then
  begin
    AKind := 'function';
  end
  else
  begin
    Exit(False);
  end;
  mText := TrimLeft(Copy(mText, Length(AKind) + 1, MaxInt));
  // Ende des Kopfs: erstes ";" außerhalb von Klammern.
  mDepth := 0;
  for mIndex := 1 to Length(mText) do
    case mText[mIndex] of
      '(': Inc(mDepth);
      ')': Dec(mDepth);
      ';':
        if mDepth = 0 then
        begin
          AHead := Trim(Copy(mText, 1, mIndex - 1));
          ADirectives := ' ' + LowerCase(Copy(mText, mIndex + 1, MaxInt)).Replace(';', ' ') + ' ';
          Exit(AHead <> '');
        end;
    end;
  Result := False;
end;

class function TInterfaceStubs.ReturnType(const AHead: string): string;
var
  mIndex, mDepth: Integer;
begin
  // Erster ":" außerhalb von Parameter- und Typparameterklammern.
  mDepth := 0;
  for mIndex := 1 to Length(AHead) do
    case AHead[mIndex] of
      '(', '<': Inc(mDepth);
      ')', '>': Dec(mDepth);
      ':':
        if mDepth = 0 then
        begin
          Exit(Trim(Copy(AHead, mIndex + 1, MaxInt)));
        end;
    end;
  Result := '';
end;

class function TInterfaceStubs.Make(const AInterfaceName, ATypeName, ADeclaration, ALineBreak: string;
  out AStub: TInterfaceStub): Boolean;
const
  // Bleiben in der Deklaration der Klasse; die Aufrufkonvention muss zu der des Interfaces passen.
  cKept: array[0..5] of string = ('overload', 'stdcall', 'safecall', 'cdecl', 'register', 'pascal');
var
  mIsClass: Boolean;
  mKind, mHead, mDirectives, mDirective, mResultType, mName: string;
begin
  AStub := Default(TInterfaceStub);
  Result := Split(ADeclaration, mIsClass, mKind, mHead, mDirectives) and not mIsClass;
  if not Result then
  begin
    Exit;
  end;
  // "Name(…): T", "Name: T", "Name<T>(…)": bis zum ersten Trennzeichen.
  mName := mHead;
  if Pos('(', mName) > 0 then
  begin
    mName := Copy(mName, 1, Pos('(', mName) - 1);
  end;
  if Pos(':', mName) > 0 then
  begin
    mName := Copy(mName, 1, Pos(':', mName) - 1);
  end;
  if Pos('<', mName) > 0 then
  begin
    mName := Copy(mName, 1, Pos('<', mName) - 1);
  end;
  AStub.InterfaceName := AInterfaceName;
  AStub.Name := Trim(mName);
  AStub.Declaration := mKind + ' ' + mHead + ';';
  for mDirective in cKept do
  begin
    if mDirectives.Contains(' ' + mDirective + ' ') then
    begin
      AStub.Declaration := AStub.Declaration + ' ' + mDirective + ';';
    end;
  end;
  // Rumpf: Standardwerte stehen nur in der Deklaration.
  AStub.Body := mKind + ' ' + ATypeName + '.' + TRegEx.Replace(mHead, '\s*=\s*[^;)]+', '') + ';' + ALineBreak +
    'begin' + ALineBreak;
  mResultType := ReturnType(mHead);
  if (mKind = 'function') and (mResultType <> '') then
  begin
    AStub.Body := AStub.Body + '  Result := Default(' + mResultType + ');' + ALineBreak;
  end
  else
  begin
    AStub.Body := AStub.Body + ALineBreak;
  end;
  AStub.Body := AStub.Body + 'end;';
end;

class function TInterfaceStubs.LastSection(const ATokens: TArray<TPascalToken>; AFirstLine,
  ALastLine: Integer): string;
var
  mIndex, mPrevious: Integer;
  mWord: string;
begin
  Result := '';
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].StartPos.Line <= AFirstLine then
    begin
      Continue;
    end;
    if ATokens[mIndex].StartPos.Line >= ALastLine then
    begin
      Break;
    end;
    if not (ATokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
    begin
      Continue;
    end;
    mWord := LowerCase(ATokens[mIndex].Text);
    if not MatchStr(mWord, ['private', 'protected', 'public', 'published']) then
    begin
      Continue;
    end;
    mPrevious := mIndex - 1;
    while (mPrevious >= 0) and (ATokens[mPrevious].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    begin
      Dec(mPrevious);
    end;
    if (mPrevious >= 0) and SameText(ATokens[mPrevious].Text, 'strict') then
    begin
      mWord := 'strict ' + mWord;
    end;
    Result := mWord;
  end;
end;

class function TInterfaceStubs.ClassEdits(const AStub: TInterfaceStub; AEndLine: Integer; const AIndent,
  ASection: string; AHeader: Boolean; const ALineBreak: string): TArray<TTextEdit>;
var
  mRange: TTextRange;
begin
  Result := nil;
  mRange := TTextRange.Create(AEndLine, 0, AEndLine, 0);
  if AHeader then
  begin
    Result := Result + [TTextEdit.Create(mRange, AIndent + ASection + ALineBreak)];
  end;
  Result := Result + [TTextEdit.Create(mRange, AIndent + '  { ' + AStub.InterfaceName + ' }' + ALineBreak),
    TTextEdit.Create(mRange, AIndent + '  ' + AStub.Declaration + ALineBreak)];
end;

function SameRange(const A, B: TTextRange): Boolean;
begin
  Result := (A.StartPos.Line = B.StartPos.Line) and (A.StartPos.Character = B.StartPos.Character) and
    (A.EndPos.Line = B.EndPos.Line) and (A.EndPos.Character = B.EndPos.Character);
end;

class function TInterfaceStubs.Merge(const AEdits: TArray<TTextEdit>): TArray<TTextEdit>;
var
  mEdit: TTextEdit;
  mIndex, mFound: Integer;
  // Je Bereich die schon übernommenen Texte, mit #0 umschlossen.
  mSeen: TArray<string>;
begin
  Result := nil;
  mSeen := nil;
  for mEdit in AEdits do
  begin
    mFound := -1;
    for mIndex := 0 to High(Result) do
    begin
      if SameRange(Result[mIndex].Range, mEdit.Range) then
      begin
        mFound := mIndex;
        Break;
      end;
    end;
    if mFound < 0 then
    begin
      Result := Result + [mEdit];
      mSeen := mSeen + [#0 + mEdit.NewText + #0];
      Continue;
    end;
    if Pos(#0 + mEdit.NewText + #0, mSeen[mFound]) > 0 then
    begin
      Continue;
    end;
    mSeen[mFound] := mSeen[mFound] + mEdit.NewText + #0;
    Result[mFound].NewText := Result[mFound].NewText + mEdit.NewText;
  end;
end;

class function TInterfaceStubs.DeclarationOf(const ALines: TArray<string>; const ARange: TTextRange): string;
const
  cMaxLines = 6;
  cMaxLength = 600;
var
  mLine, mLast: Integer;
begin
  Result := '';
  mLast := ARange.EndPos.Line;
  if mLast - ARange.StartPos.Line >= cMaxLines then
  begin
    mLast := ARange.StartPos.Line;
  end;
  for mLine := ARange.StartPos.Line to mLast do
  begin
    if (mLine < 0) or (mLine > High(ALines)) then
    begin
      Break;
    end;
    if mLine = ARange.StartPos.Line then
    begin
      Result := Trim(Copy(ALines[mLine], ARange.StartPos.Character + 1, MaxInt));
    end
    else
    begin
      Result := Result + ' ' + Trim(ALines[mLine]);
    end;
  end;
  while Pos('  ', Result) > 0 do
  begin
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  end;
  if Length(Result) > cMaxLength then
  begin
    Result := Copy(Result, 1, cMaxLength) + ' …';
  end;
end;

class function TInterfaceStubs.HeaderAncestors(const ALines: TArray<string>; AStartLine: Integer): TArray<string>;
var
  mText, mPart: string;
  mLine, mIndex, mDepth: Integer;
  mMatch: TMatch;
begin
  Result := nil;
  mText := '';
  for mLine := AStartLine to Min(AStartLine + 5, High(ALines)) do
  begin
    mText := mText + ' ' + ALines[mLine];
  end;
  mMatch := TRegEx.Match(mText, '=\s*class\s*(?:sealed\s*|abstract\s*)?\(', [roIgnoreCase]);
  if not mMatch.Success then
  begin
    Exit;
  end;
  mDepth := 0;
  mPart := '';
  for mIndex := mMatch.Index + mMatch.Length to Length(mText) do
  begin
    case mText[mIndex] of
      '(', '<':
        Inc(mDepth);
      ')', '>':
        begin
          if mDepth = 0 then
          begin
            if Trim(mPart) <> '' then
            begin
              Result := Result + [StringReplace(Trim(mPart), ' ', '', [rfReplaceAll])];
            end;
            Exit;
          end;
          Dec(mDepth);
        end;
      ',':
        if mDepth = 0 then
        begin
          Result := Result + [StringReplace(Trim(mPart), ' ', '', [rfReplaceAll])];
          mPart := '';
          Continue;
        end;
    end;
    mPart := mPart + mText[mIndex];
  end;
  Result := nil;
end;

class function TInterfaceStubs.SubstituteWords(const AText: string; const ABindings: TArray<string>): string;
var
  mBinding: string;
  mEqual: Integer;
begin
  Result := AText;
  for mBinding in ABindings do
  begin
    mEqual := Pos('=', mBinding);
    Result := TRegEx.Replace(Result, '(?<![\w.])' + TRegEx.Escape(Copy(mBinding, 1, mEqual - 1)) + '(?![\w])',
      Copy(mBinding, mEqual + 1, MaxInt).Replace('$', '$$'));
  end;
end;

class function TInterfaceStubs.GenericName(const AContainer: string; const ABindings: TArray<string>): string;
var
  mBinding: string;
  mValues: TArray<string>;
begin
  Result := AContainer;
  if Length(ABindings) = 0 then
  begin
    Exit;
  end;
  mValues := nil;
  for mBinding in ABindings do
  begin
    mValues := mValues + [Copy(mBinding, Pos('=', mBinding) + 1, MaxInt)];
  end;
  Result := Result + '<' + string.Join(', ', mValues) + '>';
end;

end.
