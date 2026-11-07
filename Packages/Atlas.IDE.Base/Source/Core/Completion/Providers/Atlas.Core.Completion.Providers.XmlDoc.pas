unit Atlas.Core.Completion.Providers.XmlDoc;

// XMLDoc-Tags in ///-Kommentaren (#435): Nach "/// <" schlägt Atlas die Tags
// vor, bei <param> je Parameter der folgenden Deklaration einen Eintrag,
// <returns> nur bei Funktionen. Lokal, ohne Server. Der Einfügetext markiert
// mit "$0", wo der Cursor danach steht (zwischen den Tags).

interface

uses
  System.SysUtils,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Internals.Async;

type
  TAtlasXmlDoc = class
  public
    /// <summary>Steht der Cursor nach "/// &lt;" (ggf. mit angefangenem Tag)? ALineBefore: Zeile bis zum
    /// Cursor.</summary>
    class function IsTagContext(const ALineBefore: string): Boolean; static;
    /// <summary>Deklaration nach der Zeile ALine (0-basiert): die nächsten Zeilen ohne ///, bis ";"
    /// außerhalb von Klammern; '' ohne.</summary>
    class function FollowingDeclaration(const AText: string; ALine: Integer): string; static;
    /// <summary>Parameternamen einer Deklaration in Reihenfolge.</summary>
    class function ParamNames(const ADeclaration: string): TArray<string>; static;
    /// <summary>Vorschläge für ADeclaration.</summary>
    class function TagItems(const ADeclaration: string): TAtlasCompletionItems; static;
  end;

  TAtlasXmlDocCompletionProvider = class(TAtlasAsyncCompletionProvider)
  public
    /// <summary>Name der Quelle für die Sicherung (#493) und ihre Meldungen, in der Sprache der Oberfläche.
    /// </summary>
    class function ProviderTitle: string; static;
    constructor Create;
  protected
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      const AEmit: TAtlasEmitProc; out AState: TAtlasFetchState): TAtlasCompletionItems; override;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Classes,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TXmlDocText = (CompletionXMLDoc);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TXmlDocText] of string = (
    ('Vervollständigung (XMLDoc)'),
    ('Completion (XMLDoc)'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TXmlDocText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

function Tag(const AName, AInsert: string; ARank: Integer): TAtlasCompletionItem;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
  Result.InsertText := AInsert;
  Result.Kind := TAtlasItemKind.XmlDocTag;
  Result.Rank := ARank;
  Result.UnitUsed := True;
end;

{ TAtlasXmlDoc }

class function TAtlasXmlDoc.IsTagContext(const ALineBefore: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if not TrimLeft(ALineBefore).StartsWith('///') then
  begin
    Exit;
  end;
  // Angefangenen Tagnamen überspringen, dann muss "<" stehen.
  mIndex := Length(ALineBefore);
  while (mIndex > 0) and CharInSet(ALineBefore[mIndex], ['A'..'Z', 'a'..'z']) do
  begin
    Dec(mIndex);
  end;
  Result := (mIndex > 0) and (ALineBefore[mIndex] = '<');
end;

class function TAtlasXmlDoc.FollowingDeclaration(const AText: string; ALine: Integer): string;
var
  mAll: TArray<string>;
  mIndex, mDepth, mPosition: Integer;
  mLine: string;
begin
  Result := '';
  mAll := Lines(AText);
  mDepth := 0;
  for mIndex := ALine + 1 to Min(High(mAll), ALine + 12) do
  begin
    mLine := Trim(mAll[mIndex]);
    if mLine.StartsWith('///') or ((Result = '') and ((mLine = '') or mLine.StartsWith('['))) then
    begin
      Continue;
    end;
    Result := Result + ' ' + mLine;
    for mPosition := 1 to Length(mLine) do
      case mLine[mPosition] of
        '(': Inc(mDepth);
        ')': Dec(mDepth);
        ';':
          if mDepth <= 0 then
          begin
            Exit(Trim(Result));
          end;
      end;
  end;
  Result := Trim(Result);
end;

class function TAtlasXmlDoc.ParamNames(const ADeclaration: string): TArray<string>;
var
  mOpen, mClose, mIndex: Integer;
  mInner, mGroup, mNames, mName: string;
begin
  Result := nil;
  mOpen := Pos('(', ADeclaration);
  if mOpen = 0 then
  begin
    Exit;
  end;
  mClose := mOpen;
  mIndex := 0;
  repeat
    case ADeclaration[mClose] of
      '(': Inc(mIndex);
      ')': Dec(mIndex);
    end;
    Inc(mClose);
  until (mIndex = 0) or (mClose > Length(ADeclaration));
  mInner := Copy(ADeclaration, mOpen + 1, mClose - mOpen - 2);
  for mGroup in mInner.Split([';']) do
  begin
    // "const A, B: string = ''" → A, B
    mNames := mGroup;
    if Pos(':', mNames) > 0 then
    begin
      mNames := Copy(mNames, 1, Pos(':', mNames) - 1);
    end;
    mNames := Trim(mNames);
    for mName in ['const ', 'var ', 'out ', 'constref '] do
    begin
      if StartsText(mName, mNames) then
      begin
        mNames := Trim(Copy(mNames, Length(mName) + 1, MaxInt));
      end;
    end;
    for mName in mNames.Split([',']) do
    begin
      if Trim(mName) <> '' then
      begin
        Result := Result + [Trim(mName)];
      end;
    end;
  end;
end;

class function TAtlasXmlDoc.TagItems(const ADeclaration: string): TAtlasCompletionItems;
var
  mName: string;
  mRank: Integer;
  mIsFunction: Boolean;
begin
  mRank := 0;
  Result := [Tag('summary', 'summary>$0</summary>', mRank)];
  for mName in ParamNames(ADeclaration) do
  begin
    Inc(mRank);
    Result := Result + [Tag(Format('param name="%s"', [mName]), Format('param name="%s">$0</param>', [mName]), mRank)];
  end;
  mIsFunction := StartsText('function ', TrimLeft(ADeclaration)) or StartsText('class function ', TrimLeft(ADeclaration));
  if mIsFunction then
  begin
    Result := Result + [Tag('returns', 'returns>$0</returns>', mRank + 1)];
  end;
  Result := Result + [Tag('remarks', 'remarks>$0</remarks>', mRank + 2),
    Tag('exception cref=""', 'exception cref="$0"></exception>', mRank + 3),
    Tag('see cref=""', 'see cref="$0"/>', mRank + 4), Tag('value', 'value>$0</value>', mRank + 5),
    Tag('para', 'para>$0</para>', mRank + 6), Tag('c', 'c>$0</c>', mRank + 7),
    Tag('code', 'code>$0</code>', mRank + 8)];
end;

{ TAtlasXmlDocCompletionProvider }

class function TAtlasXmlDocCompletionProvider.ProviderTitle: string;
begin
  Result := UiText(TXmlDocText.CompletionXMLDoc);
end;

constructor TAtlasXmlDocCompletionProvider.Create;
begin
  inherited Create;
  Name := ProviderTitle;
end;

function TAtlasXmlDocCompletionProvider.Fetch(const AContext: TAtlasContext; AData: TObject;
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc;
    out AState: TAtlasFetchState): TAtlasCompletionItems;
var
  mAll: TArray<string>;
begin
  AState := Default(TAtlasFetchState);
  Result := nil;
  mAll := Lines(AContext.Text);
  if (AContext.Line < 0) or (AContext.Line > High(mAll)) then
  begin
    Exit;
  end;
  if not TAtlasXmlDoc.IsTagContext(Copy(mAll[AContext.Line], 1, AContext.Character)) then
  begin
    Exit;
  end;
  Result := TAtlasXmlDoc.TagItems(TAtlasXmlDoc.FollowingDeclaration(AContext.Text, AContext.Line));
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Completion.Providers.XmlDoc', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
