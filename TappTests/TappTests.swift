//
//  TappTests.swift
//  TappTests
//
//  Created by Ben Ross on 11/17/25.
//

import CoreFoundation
import Testing
@testable import Tapp

struct TappTests {

  @Test func stickGroups_decomposeByFives() {
        #expect(StickTallyLogic.groups(for: 7) == [5, 2])
        #expect(StickTallyLogic.groups(for: 5) == [5])
        #expect(StickTallyLogic.groups(for: 4) == [4])
        #expect(StickTallyLogic.groups(for: 1) == [1])
        #expect(StickTallyLogic.groups(for: 0) == [])
    }

    @Test func stickGroupCount_matchesGroups() {
        #expect(CountFormatter.stickGroupCount(for: 7) == 2)
        #expect(CountFormatter.stickGroupCount(for: 78) == 16)
        #expect(CountFormatter.stickGroupCount(for: 0) == 0)
    }

    @Test func stickFormatter_stringUsesArabic() {
        #expect(CountFormatter.string(for: 42, numberType: UserNumberType.stick) == "42")
    }

    @Test func stickLayout_fitsSmallCountsWithoutOverflow() {
        let result = StickTallyLayout.fit(
            groupCount: 2,
            maxWidth: 148,
            maxHeight: 36,
            maxGroupHeight: 22
        )
        #expect(result.showArabicOverflow == false)
        #expect(result.visibleGroupCount == 2)
        #expect(result.totalGroupCount == 2)
    }

    @Test func paletteMeetsContrastOnTintedRows() {
        #expect(ColorContrast.paletteSwatchesMeetAAOnTintedRows())
    }

    @Test func stickLayout_overflowWhenManyGroups() {
        let groupCount = CountFormatter.stickGroupCount(for: 78)
        let result = StickTallyLayout.fit(
            groupCount: groupCount,
            maxWidth: 60,
            maxHeight: 36,
            maxGroupHeight: 22
        )
        #expect(result.showArabicOverflow == true)
        #expect(result.visibleGroupCount < groupCount)
        #expect(result.visibleGroupCount > 0)
    }
}
