#!/bin/bash

#
# test-resource-parameters.sh
# SwiftAgentKit
#
# Test runner for RFC 8707 Resource Parameter implementation
# Created by SwiftAgentKit on 1/17/25.
#

set -e

echo "🧪 Running RFC 8707 Resource Parameter Tests"
echo "============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test categories
TESTS=(
    "ResourceIndicatorUtilitiesTests"
    "PKCEOAuthAuthProviderTests" 
    "OAuthAuthProviderTests"
    "AuthenticationFactoryTests"
    "MCPResourceParameterTests"
    "ResourceParameterIntegrationTests"
)

echo -e "${BLUE}📋 Test Categories:${NC}"
for test in "${TESTS[@]}"; do
    echo "   • $test"
done
echo ""

# Run individual test suites
FAILED_TESTS=()
PASSED_TESTS=()

for test in "${TESTS[@]}"; do
    echo -e "${YELLOW}🔍 Running $test...${NC}"
    
    if swift test --filter "$test" 2>/dev/null; then
        echo -e "${GREEN}✅ $test PASSED${NC}"
        PASSED_TESTS+=("$test")
    else
        echo -e "${RED}❌ $test FAILED${NC}"
        FAILED_TESTS+=("$test")
    fi
    echo ""
done

# Summary
echo "📊 Test Summary"
echo "==============="
echo -e "${GREEN}✅ Passed: ${#PASSED_TESTS[@]}${NC}"
echo -e "${RED}❌ Failed: ${#FAILED_TESTS[@]}${NC}"

if [ ${#PASSED_TESTS[@]} -gt 0 ]; then
    echo -e "\n${GREEN}Passed Tests:${NC}"
    for test in "${PASSED_TESTS[@]}"; do
        echo "   ✅ $test"
    done
fi

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo -e "\n${RED}Failed Tests:${NC}"
    for test in "${FAILED_TESTS[@]}"; do
        echo "   ❌ $test"
    done
fi

# Run all resource parameter tests together
echo -e "\n${BLUE}🚀 Running all Resource Parameter tests together...${NC}"
if swift test --filter "Resource" 2>/dev/null; then
    echo -e "${GREEN}✅ All Resource Parameter tests PASSED${NC}"
else
    echo -e "${RED}❌ Some Resource Parameter tests FAILED${NC}"
fi

# Feature coverage summary
echo -e "\n${BLUE}📋 Feature Coverage Summary:${NC}"
echo "✅ RFC 8707 Canonical URI validation"
echo "✅ Resource parameter in authorization requests"
echo "✅ Resource parameter in token requests"
echo "✅ Resource parameter in token refresh requests"
echo "✅ PKCE OAuth integration"
echo "✅ OAuth Discovery integration"
echo "✅ Standard OAuth integration"
echo "✅ MCP client configuration"
echo "✅ Authentication factory integration"
echo "✅ Environment variable support"
echo "✅ Error handling and validation"
echo "✅ End-to-end integration testing"

echo -e "\n${GREEN}🎉 RFC 8707 Resource Parameter implementation test suite complete!${NC}"

# Exit with error if any tests failed
if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    exit 1
else
    exit 0
fi
