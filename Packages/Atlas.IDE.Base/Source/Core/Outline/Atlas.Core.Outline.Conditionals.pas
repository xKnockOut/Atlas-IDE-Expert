unit Atlas.Core.Outline.Conditionals;

// Bedingungszweige am Caret für die Brotkrumenleiste (#1763), Kern ohne VCL
// und OTA:
// - Ein Block besteht aus {$IF…} ({$IFDEF}, {$IFNDEF}, {$IF}, {$IFOPT}), den
//   Zweigen {$ELSEIF}/{$ELSE} und {$ENDIF}/{$IFEND}; ohne Ende reicht er bis
//   zum Ende des Texts. Direktiven aus TAtlasDirectiveScanner.
// - At liefert die Blöcke um die Stelle, außen zuerst: Text des Zweigs
//   („{$IFDEF MSWINDOWS}“, im Gegenzweig „{$ELSE MSWINDOWS}“, bei {$ELSEIF}
//   dessen Bedingung) und die Teile des Blocks als Sprungziele.
// - Die Stelle liegt in einem Zweig, wenn sie hinter seiner Direktive und vor
//   der nächsten Direktive des Blocks steht. Ob der Zweig aktiv ist,
//   entscheidet At nicht.

interface

type
  /// <summary>Teil eines Bedingungsblocks (IF, ELSEIF, ELSE, ENDIF) als Sprungziel.</summary>
  TAtlasConditionalPart = record
    /// <summary>Direktive wie geschrieben, gekürzt („{$IFDEF DEBUG}“).</summary>
    Text: string;
    /// <summary>Anfang der Direktive, 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
  end;

  /// <summary>Zweig eines Bedingungsblocks an einer Stelle.</summary>
  TAtlasConditionalBranch = record
    /// <summary>Text des Glieds („{$ELSE MSWINDOWS}“).</summary>
    Text: string;
    /// <summary>Teile des Blocks in Quelltextreihenfolge.</summary>
    Parts: TArray<TAtlasConditionalPart>;
    /// <summary>Index des Teils, mit dem der Zweig beginnt.</summary>
    Current: Integer;
  end;

  TAtlasConditionalBranches = TArray<TAtlasConditionalBranch>;

  TAtlasConditionalFinder = class
  public
    /// <summary>Zweige um ALine/ACharacter (0-basiert), außen zuerst; leer außerhalb jeder Bedingung.</summary>
    class function At(const ALines: TArray<string>; ALine, ACharacter: Integer): TAtlasConditionalBranches; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Outline.Directives,
  Atlas.Core.Outline.TypeText;

const
  /// <summary>Längste Bedingung im Text eines Glieds; danach „…“.</summary>
  cMaxArgument = 40;

type
  /// <summary>Bedingungsblock: Indizes seiner Direktiven, Closed mit ENDIF/IFEND.</summary>
  TBlock = record
    Parts: TArray<Integer>;
    Closed: Boolean;
  end;

function IsOpening(const AName: string): Boolean;
begin
  Result := (AName = 'IF') or (AName = 'IFDEF') or (AName = 'IFNDEF') or (AName = 'IFOPT');
end;

function IsBranch(const AName: string): Boolean;
begin
  Result := (AName = 'ELSE') or (AName = 'ELSEIF');
end;

function IsClosing(const AName: string): Boolean;
begin
  Result := (AName = 'ENDIF') or (AName = 'IFEND');
end;

function Shortened(const AText: string): string;
begin
  Result := AText;
  if Length(Result) > cMaxArgument then
  begin
    Result := Copy(Result, 1, cMaxArgument) + '…';
  end;
end;

function DirectiveText(const AName, AArgument: string): string;
begin
  Result := '{$' + AName;
  if AArgument <> '' then
  begin
    Result := Result + ' ' + Shortened(AArgument);
  end;
  Result := Result + '}';
end;

/// <summary>Blöcke aus den Direktiven; innere stehen hinter ihren äußeren.</summary>
function BlocksOf(const ADirectives: TAtlasDirectives): TArray<TBlock>;
var
  mIndex: Integer;
  mOpen: TArray<Integer>;
  mName: string;
  mBlock: TBlock;
begin
  Result := nil;
  mOpen := nil;
  for mIndex := 0 to High(ADirectives) do
  begin
    mName := ADirectives[mIndex].Name;
    if IsOpening(mName) then
    begin
      mBlock.Parts := [mIndex];
      mBlock.Closed := False;
      Result := Result + [mBlock];
      mOpen := mOpen + [High(Result)];
    end
    else if (IsBranch(mName) or IsClosing(mName)) and (Length(mOpen) > 0) then
    begin
      Result[mOpen[High(mOpen)]].Parts := Result[mOpen[High(mOpen)]].Parts + [mIndex];
      if IsClosing(mName) then
      begin
        Result[mOpen[High(mOpen)]].Closed := True;
        SetLength(mOpen, Length(mOpen) - 1);
      end;
    end;
  end;
end;

/// <summary>Zweig des Blocks ABlock an der Stelle; -1, wenn sie nicht darin liegt.</summary>
function BranchAt(const ADirectives: TAtlasDirectives; const ABlock: TBlock; ALine, ACharacter: Integer): Integer;
var
  mIndex: Integer;
  mPart: TAtlasDirective;
begin
  Result := -1;
  for mIndex := 0 to High(ABlock.Parts) do
  begin
    mPart := ADirectives[ABlock.Parts[mIndex]];
    if TAtlasTypeText.Before(ALine, ACharacter, mPart.EndLine, mPart.EndCharacter) then
    begin
      // Vor dem Ende dieser Direktive: im vorigen Zweig, wenn die Stelle vor ihrem Anfang liegt.
      if (Result >= 0) and not TAtlasTypeText.Before(ALine, ACharacter, mPart.Line, mPart.Character) then
      begin
        Result := -1;
      end;
      Exit;
    end;
    Result := mIndex;
  end;
  // Hinter ENDIF: außerhalb.
  if ABlock.Closed then
  begin
    Result := -1;
  end;
end;

/// <summary>Zweig ACurrent des Blocks ABlock mit Text und Sprungzielen.</summary>
function BranchOf(const ADirectives: TAtlasDirectives; const ABlock: TBlock;
  ACurrent: Integer): TAtlasConditionalBranch;
var
  mIndex: Integer;
  mDirective, mOpening: TAtlasDirective;
  mPart: TAtlasConditionalPart;
begin
  Result.Parts := nil;
  for mIndex in ABlock.Parts do
  begin
    mDirective := ADirectives[mIndex];
    mPart.Text := DirectiveText(mDirective.Name, mDirective.Argument);
    mPart.Line := mDirective.Line;
    mPart.Character := mDirective.Character;
    Result.Parts := Result.Parts + [mPart];
  end;
  Result.Current := ACurrent;
  mDirective := ADirectives[ABlock.Parts[ACurrent]];
  Result.Text := Result.Parts[ACurrent].Text;
  if mDirective.Name = 'ELSE' then
  begin
    // Gegenzweig mit der Bedingung des Blocks.
    mOpening := ADirectives[ABlock.Parts[0]];
    Result.Text := DirectiveText('ELSE', mOpening.Argument);
  end;
end;

class function TAtlasConditionalFinder.At(const ALines: TArray<string>; ALine,
  ACharacter: Integer): TAtlasConditionalBranches;
var
  mDirectives: TAtlasDirectives;
  mBlock: TBlock;
  mBranch: Integer;
begin
  Result := nil;
  mDirectives := TAtlasDirectiveScanner.Scan(ALines);
  for mBlock in BlocksOf(mDirectives) do
  begin
    mBranch := BranchAt(mDirectives, mBlock, ALine, ACharacter);
    if mBranch >= 0 then
    begin
      Result := Result + [BranchOf(mDirectives, mBlock, mBranch)];
    end;
  end;
end;

end.
