unit Atlas.Core.Designer.NameSuggest;

// Sprechende Komponentennamen vorschlagen (#608), ohne VCL und Windows.
// - Standardname: Klasse ohne „T“ plus Ziffern (Button1, Edit3).
// - Vorschlag = Präfix der Klasse + ein Wort in PascalCase aus der ersten
//   Quelle mit Text, in der eingestellten Reihenfolge: Caption/Text,
//   zugeordnetes Label, sprechender Handler, DataField.
// - Präfix: eingebaute Tabelle (btn, edt, lbl …), überschreibbar mit
//   „TMyButton=btn, TEdit=ed“; gesucht wird die Klasse, dann ihre Vorfahren,
//   sonst die ersten drei Buchstaben der Klasse ohne „T“.
// - Wort: „&“ der Tastenkürzel entfällt, Trennzeichen trennen Wörter, höchstens
//   drei Wörter; ganz großgeschriebene Wörter werden zu „Plz“. Umlaute
//   ersetzt (ä → ae, ß → ss) oder entfernt, andere Zeichen außerhalb von
//   A–Z, a–z, 0–9 entfallen.
// - Label: zuerst eines mit FocusControl auf die Komponente, sonst im selben
//   Parent links in derselben Zeile oder direkt darüber, das nächste.
// - Kollision mit einem vorhandenen oder schon vergebenen Namen: Nummer ab 2.
// - Umbenennen im Code: Handler mit Standardnamen ziehen mit
//   (Button1Click → btnSpeichernClick); Stellen eines Bezeichners im Text ohne
//   Zeichenketten und Kommentare.

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasNameSource = (None, Caption, LabelText, Handler, DataField);
  TAtlasUmlautRule = (Replace, Remove);
{$SCOPEDENUMS OFF}

  TAtlasNameLabel = record
    Caption: string;
    Bounds: TRect;
    ParentName: string;
    /// <summary>Name aus FocusControl; leer ohne.</summary>
    FocusControl: string;
  end;

  TAtlasNameInput = record
    Name: string;
    /// <summary>Klasse und Vorfahren, die Klasse zuerst.</summary>
    ClassChain: TArray<string>;
    /// <summary>Caption bzw. Text.</summary>
    Caption: string;
    /// <summary>Beschriftung des zugeordneten Labels.</summary>
    LabelText: string;
    /// <summary>Namen der zugewiesenen Handler.</summary>
    Handlers: TArray<string>;
    DataField: string;
  end;

  TAtlasNameProposal = record
    OldName: string;
    /// <summary>Leer ohne passende Quelle.</summary>
    NewName: string;
    Source: TAtlasNameSource;
    /// <summary>Nummer wegen eines gleichen Namens angehängt.</summary>
    Collision: Boolean;
  end;

  TAtlasNameOptions = record
    Sources: TArray<TAtlasNameSource>;
    Umlauts: TAtlasUmlautRule;
    /// <summary>Eigene Präfixe „TKlasse=präfix, …“ vor der eingebauten Tabelle.</summary>
    Prefixes: string;
  end;

  /// <summary>Stelle eines Bezeichners im Text, 0-basiert.</summary>
  TAtlasNamePlace = record
    Line: Integer;
    Character: Integer;
  end;

  TAtlasNameSuggest = class
  public const
    cMaxWords = 3;
    /// <summary>Größter Abstand eines Labels links von der Komponente.</summary>
    cLeftGap = 32;
    /// <summary>Größter Abstand eines Labels über der Komponente.</summary>
    cAboveGap = 12;
    /// <summary>Größter Versatz der linken Kanten bei einem Label darüber.</summary>
    cAboveShift = 16;
  public
    /// <summary>Button1 bei TButton, Edit3 bei TEdit.</summary>
    class function IsDefaultName(const AName, AClassName: string): Boolean; static;
    /// <summary>Präfix zur Klasse oder einem Vorfahren.</summary>
    class function Prefix(const AClassChain: TArray<string>; const ACustom: string): string; static;
    /// <summary>Wort in PascalCase aus AText; leer, wenn nichts übrig bleibt.</summary>
    class function Word(const AText: string; AUmlauts: TAtlasUmlautRule): string; static;
    /// <summary>Wort aus einem sprechenden Handler („DoExport“ → „Export“); leer bei einem Standardnamen, der mit
    /// AComponent beginnt.</summary>
    class function HandlerWord(const AHandler, AComponent: string): string; static;
    /// <summary>Quellen aus „caption, label, handler, dataField“; Unbekanntes entfällt.</summary>
    class function ParseSources(const AText: string): TArray<TAtlasNameSource>; static;
    /// <summary>Beschriftung des Labels für die Komponente AName mit ABounds im Parent AParent; leer ohne.</summary>
    class function LabelFor(const AName, AParent: string; const ABounds: TRect;
      const ALabels: TArray<TAtlasNameLabel>): string; static;
    /// <summary>Vorschläge für alle AInputs; ATaken sind die vorhandenen Namen des Formulars.</summary>
    class function Propose(const AInputs: TArray<TAtlasNameInput>; const AOptions: TAtlasNameOptions;
      const ATaken: TArray<string>): TArray<TAtlasNameProposal>; static;
    /// <summary>Neuer Name eines Handlers, wenn er mit AOldName beginnt (Standardname); sonst leer.</summary>
    class function HandlerName(const AHandler, AOldName, ANewName: string): string; static;
    /// <summary>Stellen des Bezeichners AName in AText außerhalb von Zeichenketten und Kommentaren.</summary>
    class function Places(const AText, AName: string): TArray<TAtlasNamePlace>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Character,
  Atlas.Core.Designer.FitText;

type
  TPrefixEntry = record
    ClassName: string;
    Prefix: string;
  end;

const
  cPrefixLength = 3;
  cDefaultPrefixes: array[0..55] of TPrefixEntry = (
    (ClassName: 'TButton'; Prefix: 'btn'), (ClassName: 'TBitBtn'; Prefix: 'btn'),
    (ClassName: 'TSpeedButton'; Prefix: 'btn'), (ClassName: 'TToolButton'; Prefix: 'tbt'),
    (ClassName: 'TLabeledEdit'; Prefix: 'edt'), (ClassName: 'TMaskEdit'; Prefix: 'edt'),
    (ClassName: 'TDBEdit'; Prefix: 'edt'), (ClassName: 'TEdit'; Prefix: 'edt'),
    (ClassName: 'TSpinEdit'; Prefix: 'sed'), (ClassName: 'TButtonedEdit'; Prefix: 'edt'),
    (ClassName: 'TLabel'; Prefix: 'lbl'), (ClassName: 'TDBText'; Prefix: 'lbl'),
    (ClassName: 'TStaticText'; Prefix: 'lbl'), (ClassName: 'TLinkLabel'; Prefix: 'lbl'),
    (ClassName: 'TMemo'; Prefix: 'mmo'), (ClassName: 'TDBMemo'; Prefix: 'mmo'),
    (ClassName: 'TRichEdit'; Prefix: 'mmo'), (ClassName: 'TCheckBox'; Prefix: 'chk'),
    (ClassName: 'TDBCheckBox'; Prefix: 'chk'), (ClassName: 'TRadioButton'; Prefix: 'rbt'),
    (ClassName: 'TRadioGroup'; Prefix: 'rgp'), (ClassName: 'TDBRadioGroup'; Prefix: 'rgp'),
    (ClassName: 'TComboBox'; Prefix: 'cbo'), (ClassName: 'TDBComboBox'; Prefix: 'cbo'),
    (ClassName: 'TDBLookupComboBox'; Prefix: 'cbo'), (ClassName: 'TComboBoxEx'; Prefix: 'cbo'),
    (ClassName: 'TListBox'; Prefix: 'lst'), (ClassName: 'TDBListBox'; Prefix: 'lst'),
    (ClassName: 'TCheckListBox'; Prefix: 'lst'), (ClassName: 'TListView'; Prefix: 'lvw'),
    (ClassName: 'TTreeView'; Prefix: 'tvw'), (ClassName: 'TPanel'; Prefix: 'pnl'),
    (ClassName: 'TGroupBox'; Prefix: 'grp'), (ClassName: 'TScrollBox'; Prefix: 'sbx'),
    (ClassName: 'TPageControl'; Prefix: 'pgc'), (ClassName: 'TTabSheet'; Prefix: 'tab'),
    (ClassName: 'TImage'; Prefix: 'img'), (ClassName: 'TStringGrid'; Prefix: 'grd'),
    (ClassName: 'TDrawGrid'; Prefix: 'grd'), (ClassName: 'TDBGrid'; Prefix: 'grd'),
    (ClassName: 'TDateTimePicker'; Prefix: 'dtp'), (ClassName: 'TSplitter'; Prefix: 'spl'),
    (ClassName: 'TTrackBar'; Prefix: 'trb'), (ClassName: 'TProgressBar'; Prefix: 'prb'),
    (ClassName: 'TStatusBar'; Prefix: 'stb'), (ClassName: 'TToolBar'; Prefix: 'tbr'),
    (ClassName: 'TTimer'; Prefix: 'tmr'), (ClassName: 'TActionList'; Prefix: 'acl'),
    (ClassName: 'TAction'; Prefix: 'act'), (ClassName: 'TMainMenu'; Prefix: 'mnu'),
    (ClassName: 'TPopupMenu'; Prefix: 'pmn'), (ClassName: 'TMenuItem'; Prefix: 'mni'),
    (ClassName: 'TDataSource'; Prefix: 'dsr'), (ClassName: 'TOpenDialog'; Prefix: 'dlg'),
    (ClassName: 'TSaveDialog'; Prefix: 'dlg'), (ClassName: 'TImageList'; Prefix: 'iml'));
  cSourceKeys: array[TAtlasNameSource] of string = ('', 'caption', 'label', 'handler', 'dataField');
  cHandlerPrefixes: array[0..2] of string = ('Do', 'On', 'Handle');
  cHandlerSuffixes: array[0..8] of string = ('DblClick', 'Click', 'Change', 'Execute', 'Exit', 'Enter',
    'KeyPress', 'KeyDown', 'Select');
  cUmlauts = #$00E4#$00F6#$00FC#$00C4#$00D6#$00DC#$00DF; // ä ö ü Ä Ö Ü ß
  cUmlautTexts: array[1..7] of string = ('ae', 'oe', 'ue', 'Ae', 'Oe', 'Ue', 'ss');

function IsAsciiLetterOrDigit(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9']);
end;

class function TAtlasNameSuggest.IsDefaultName(const AName, AClassName: string): Boolean;
var
  mBase: string;
  mIndex: Integer;
begin
  mBase := AClassName;
  if mBase.StartsWith('T') then
  begin
    mBase := mBase.Substring(1);
  end;
  if (mBase = '') or (Length(AName) <= Length(mBase)) or not SameText(Copy(AName, 1, Length(mBase)), mBase) then
  begin
    Exit(False);
  end;
  for mIndex := Length(mBase) + 1 to Length(AName) do
  begin
    if not CharInSet(AName[mIndex], ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function CustomPrefix(const ACustom, AClassName: string; out APrefix: string): Boolean;
var
  mPart: string;
  mPair: TArray<string>;
begin
  for mPart in ACustom.Split([',', ';']) do
  begin
    mPair := mPart.Split(['=']);
    if (Length(mPair) = 2) and SameText(mPair[0].Trim, AClassName) and (mPair[1].Trim <> '') then
    begin
      APrefix := mPair[1].Trim;
      Exit(True);
    end;
  end;
  APrefix := '';
  Result := False;
end;

function DefaultPrefix(const AClassName: string; out APrefix: string): Boolean;
var
  mEntry: TPrefixEntry;
begin
  for mEntry in cDefaultPrefixes do
  begin
    if SameText(mEntry.ClassName, AClassName) then
    begin
      APrefix := mEntry.Prefix;
      Exit(True);
    end;
  end;
  APrefix := '';
  Result := False;
end;

class function TAtlasNameSuggest.Prefix(const AClassChain: TArray<string>; const ACustom: string): string;
var
  mClass: string;
begin
  for mClass in AClassChain do
  begin
    if CustomPrefix(ACustom, mClass, Result) or DefaultPrefix(mClass, Result) then
    begin
      Exit;
    end;
  end;
  Result := '';
  if Length(AClassChain) > 0 then
  begin
    Result := AClassChain[0];
    if Result.StartsWith('T') then
    begin
      Result := Result.Substring(1);
    end;
    Result := Copy(Result, 1, cPrefixLength).ToLower;
  end;
end;

/// <summary>Umlaute nach ARule, andere Zeichen außer A–Z, a–z und 0–9 als Leerzeichen bzw. entfernt.</summary>
function Plain(const AText: string; ARule: TAtlasUmlautRule): string;
var
  mChar: Char;
  mUmlaut: Integer;
begin
  Result := '';
  for mChar in AText do
  begin
    mUmlaut := Pos(mChar, cUmlauts);
    if mUmlaut > 0 then
    begin
      if ARule = TAtlasUmlautRule.Replace then
      begin
        Result := Result + cUmlautTexts[mUmlaut];
      end;
    end
    else if IsAsciiLetterOrDigit(mChar) then
    begin
      Result := Result + mChar;
    end
    else if not mChar.IsLetter then
    begin
      Result := Result + ' ';
    end;
  end;
end;

function IsAllUpper(const AText: string): Boolean;
begin
  Result := (AText = AText.ToUpper) and (AText <> AText.ToLower);
end;

class function TAtlasNameSuggest.Word(const AText: string; AUmlauts: TAtlasUmlautRule): string;
var
  mPart: string;
  mCount: Integer;
begin
  Result := '';
  mCount := 0;
  for mPart in Plain(TAtlasFitText.StripAccel(AText).Replace('_', ' '), AUmlauts).Split([' '],
    TStringSplitOptions.ExcludeEmpty) do
  begin
    if mCount >= cMaxWords then
    begin
      Break;
    end;
    if IsAllUpper(mPart) and (Length(mPart) > 1) then
    begin
      Result := Result + mPart.Substring(0, 1) + mPart.Substring(1).ToLower;
    end
    else
    begin
      Result := Result + mPart.Substring(0, 1).ToUpper + mPart.Substring(1);
    end;
    Inc(mCount);
  end;
end;

class function TAtlasNameSuggest.HandlerWord(const AHandler, AComponent: string): string;
var
  mAffix: string;
begin
  Result := AHandler;
  if (Result = '') or ((AComponent <> '') and StartsText(AComponent, Result)) then
  begin
    Exit('');
  end;
  for mAffix in cHandlerPrefixes do
  begin
    if Result.StartsWith(mAffix) and (Length(Result) > Length(mAffix)) and
      Result.Chars[Length(mAffix)].IsUpper then
    begin
      Result := Result.Substring(Length(mAffix));
      Break;
    end;
  end;
  for mAffix in cHandlerSuffixes do
  begin
    if Result.EndsWith(mAffix) and (Length(Result) > Length(mAffix)) then
    begin
      Result := Result.Substring(0, Length(Result) - Length(mAffix));
      Break;
    end;
  end;
end;

class function TAtlasNameSuggest.ParseSources(const AText: string): TArray<TAtlasNameSource>;
var
  mPart: string;
  mSource: TAtlasNameSource;
begin
  Result := nil;
  for mPart in AText.Split([',', ';', ' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    for mSource := Succ(TAtlasNameSource.None) to High(TAtlasNameSource) do
    begin
      if SameText(mPart.Trim, cSourceKeys[mSource]) then
      begin
        Result := Result + [mSource];
      end;
    end;
  end;
end;

/// <summary>Abstand eines Labels links in derselben Zeile bzw. darüber; -1, wenn es nicht passt.</summary>
function LabelGap(const ALabel, ABounds: TRect): Integer;
var
  mMid: Integer;
begin
  mMid := ABounds.Top + ABounds.Height div 2;
  if (ALabel.Right <= ABounds.Left) and (ABounds.Left - ALabel.Right <= TAtlasNameSuggest.cLeftGap) and
    (ALabel.Top <= mMid) and (ALabel.Bottom >= mMid) then
  begin
    Exit(ABounds.Left - ALabel.Right);
  end;
  if (ALabel.Bottom <= ABounds.Top) and (ABounds.Top - ALabel.Bottom <= TAtlasNameSuggest.cAboveGap) and
    (Abs(ALabel.Left - ABounds.Left) <= TAtlasNameSuggest.cAboveShift) then
  begin
    // Darüber zählt hinter jedem passenden Label links.
    Exit(TAtlasNameSuggest.cLeftGap + ABounds.Top - ALabel.Bottom);
  end;
  Result := -1;
end;

class function TAtlasNameSuggest.LabelFor(const AName, AParent: string; const ABounds: TRect;
  const ALabels: TArray<TAtlasNameLabel>): string;
var
  mLabel: TAtlasNameLabel;
  mGap, mBest: Integer;
begin
  for mLabel in ALabels do
  begin
    if (mLabel.FocusControl <> '') and SameText(mLabel.FocusControl, AName) then
    begin
      Exit(mLabel.Caption);
    end;
  end;
  Result := '';
  mBest := MaxInt;
  for mLabel in ALabels do
  begin
    if not SameText(mLabel.ParentName, AParent) then
    begin
      Continue;
    end;
    mGap := LabelGap(mLabel.Bounds, ABounds);
    if (mGap >= 0) and (mGap < mBest) then
    begin
      mBest := mGap;
      Result := mLabel.Caption;
    end;
  end;
end;

function WordOf(const AInput: TAtlasNameInput; ASource: TAtlasNameSource; AUmlauts: TAtlasUmlautRule): string;
var
  mHandler: string;
begin
  Result := '';
  case ASource of
    TAtlasNameSource.None:
      Result := '';
    TAtlasNameSource.Caption:
      Result := TAtlasNameSuggest.Word(AInput.Caption, AUmlauts);
    TAtlasNameSource.LabelText:
      Result := TAtlasNameSuggest.Word(AInput.LabelText, AUmlauts);
    TAtlasNameSource.Handler:
      for mHandler in AInput.Handlers do
      begin
        Result := TAtlasNameSuggest.Word(TAtlasNameSuggest.HandlerWord(mHandler, AInput.Name), AUmlauts);
        if Result <> '' then
        begin
          Break;
        end;
      end;
    TAtlasNameSource.DataField:
      Result := TAtlasNameSuggest.Word(AInput.DataField, AUmlauts);
  end;
end;

function IsTaken(const ATaken: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in ATaken do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasNameSuggest.Propose(const AInputs: TArray<TAtlasNameInput>; const AOptions: TAtlasNameOptions;
  const ATaken: TArray<string>): TArray<TAtlasNameProposal>;
var
  mTaken: TArray<string>;
  mIndex, mNumber: Integer;
  mSource: TAtlasNameSource;
  mWord, mBase: string;
begin
  mTaken := Copy(ATaken);
  SetLength(Result, Length(AInputs));
  for mIndex := 0 to High(AInputs) do
  begin
    Result[mIndex] := Default(TAtlasNameProposal);
    Result[mIndex].OldName := AInputs[mIndex].Name;
    mWord := '';
    for mSource in AOptions.Sources do
    begin
      mWord := WordOf(AInputs[mIndex], mSource, AOptions.Umlauts);
      if mWord <> '' then
      begin
        Result[mIndex].Source := mSource;
        Break;
      end;
    end;
    if mWord = '' then
    begin
      Continue;
    end;
    mBase := Prefix(AInputs[mIndex].ClassChain, AOptions.Prefixes) + mWord;
    Result[mIndex].NewName := mBase;
    mNumber := 1;
    while IsTaken(mTaken, Result[mIndex].NewName) and not SameText(Result[mIndex].NewName, AInputs[mIndex].Name) do
    begin
      Inc(mNumber);
      Result[mIndex].NewName := mBase + IntToStr(mNumber);
      Result[mIndex].Collision := True;
    end;
    mTaken := mTaken + [Result[mIndex].NewName];
  end;
end;

class function TAtlasNameSuggest.HandlerName(const AHandler, AOldName, ANewName: string): string;
begin
  Result := '';
  if (AOldName <> '') and StartsText(AOldName, AHandler) and (Length(AHandler) > Length(AOldName)) then
  begin
    Result := ANewName + AHandler.Substring(Length(AOldName));
  end;
end;

function IsIdentChar(AChar: Char): Boolean;
begin
  Result := IsAsciiLetterOrDigit(AChar) or (AChar = '_');
end;

/// <summary>Von AIndex (auf dem öffnenden Zeichen) bis hinter ACloser; zählt die Zeilen weiter.</summary>
procedure SkipComment(const AText, ACloser: string; var AIndex, ALine, ALineStart: Integer);
begin
  Inc(AIndex);
  while AIndex <= Length(AText) do
  begin
    if Copy(AText, AIndex, Length(ACloser)) = ACloser then
    begin
      Inc(AIndex, Length(ACloser));
      Exit;
    end;
    if AText[AIndex] = #10 then
    begin
      Inc(ALine);
      ALineStart := AIndex + 1;
    end;
    Inc(AIndex);
  end;
end;

class function TAtlasNameSuggest.Places(const AText, AName: string): TArray<TAtlasNamePlace>;
var
  mIndex, mLine, mLineStart, mLength: Integer;
  mChar: Char;
  mPlace: TAtlasNamePlace;
begin
  Result := nil;
  mLength := Length(AName);
  if mLength = 0 then
  begin
    Exit;
  end;
  mIndex := 1;
  mLine := 0;
  mLineStart := 1;
  while mIndex <= Length(AText) do
  begin
    mChar := AText[mIndex];
    if mChar = #10 then
    begin
      Inc(mLine);
      mLineStart := mIndex + 1;
      Inc(mIndex);
    end
    else if mChar = '''' then
    begin
      // Zeichenkette bis zum schließenden Hochkomma ('' ist ein Hochkomma darin) oder Zeilenende.
      Inc(mIndex);
      while (mIndex <= Length(AText)) and (AText[mIndex] <> '''') and (AText[mIndex] <> #10) do
      begin
        Inc(mIndex);
      end;
      if (mIndex <= Length(AText)) and (AText[mIndex] = '''') then
      begin
        Inc(mIndex);
      end;
    end
    else if (mChar = '/') and (mIndex < Length(AText)) and (AText[mIndex + 1] = '/') then
    begin
      while (mIndex <= Length(AText)) and (AText[mIndex] <> #10) do
      begin
        Inc(mIndex);
      end;
    end
    else if mChar = '{' then
    begin
      SkipComment(AText, '}', mIndex, mLine, mLineStart);
    end
    else if (mChar = '(') and (mIndex < Length(AText)) and (AText[mIndex + 1] = '*') then
    begin
      Inc(mIndex);
      SkipComment(AText, '*)', mIndex, mLine, mLineStart);
    end
    else if IsIdentChar(mChar) then
    begin
      if ((mIndex = 1) or not IsIdentChar(AText[mIndex - 1])) and SameText(Copy(AText, mIndex, mLength), AName) and
        ((mIndex + mLength > Length(AText)) or not IsIdentChar(AText[mIndex + mLength])) then
      begin
        mPlace.Line := mLine;
        mPlace.Character := mIndex - mLineStart;
        Result := Result + [mPlace];
        Inc(mIndex, mLength);
      end
      else
      begin
        while (mIndex <= Length(AText)) and IsIdentChar(AText[mIndex]) do
        begin
          Inc(mIndex);
        end;
      end;
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
end;

end.
