#include <gtest/gtest.h>
#include "math_operations.h"

TEST(AddTest, PositiveNumbers) {
    EXPECT_EQ(add(2, 3), 5);
}

TEST(AddTest, NegativeNumbers) {
    EXPECT_EQ(add(-2, -3), -5);
}

TEST(AddTest, MixedSign) {
    EXPECT_EQ(add(-2, 3), 1);
    EXPECT_EQ(add(2, -3), -1);
}

TEST(AddTest, WithZero) {
    EXPECT_EQ(add(0, 0), 0);
    EXPECT_EQ(add(0, 5), 5);
    EXPECT_EQ(add(5, 0), 5);
}

TEST(AddTest, LargeNumbers) {
    EXPECT_EQ(add(1000000, 2000000), 3000000);
}

int main(int argc, char **argv) {
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
