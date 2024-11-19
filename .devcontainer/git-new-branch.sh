#!/bin/bash
echo "Select branch type:"
echo "1) feature"
echo "2) fix"
echo "3) docs"
echo "4) style"
echo "5) refactor"
echo "6) test"
echo "7) chore"
read -p "Enter the number of your choice: " choice

case $choice in
    1) type="feature" ;;
    2) type="fix" ;;
    3) type="docs" ;;
    4) type="style" ;;
    5) type="refactor" ;;
    6) type="test" ;;
    7) type="chore" ;;
    *) echo "Invalid choice. Exiting."; exit 1 ;;
esac

read -p "Enter a brief description (use-hyphens-for-spaces): " description

branch_name="${type}/${description}"
git checkout -b "$branch_name"
git push -u origin "$branch_name"
echo "Created, pushed, and set upstream for branch: $branch_name"
